import AVFoundation
import Observation
import OSLog
import Vision

/// 손떨림 보정(#71)을 위한 원본 움직임 분석. 기기 안(Vision 프레임 정합)에서 이웃 프레임 사이 이동을 재 누적하고,
/// 결과는 프로젝트가 아니라 앱 캐시(Application Support/Stabilization/<원본 캐시 키>.json)에 둔다 — 프록시처럼 같은 파일이면 함께 쓴다.
/// 분석은 뒤에서 진행률과 함께 하고, 끝나면 미리보기가 다시 합성해 보정이 보인다.
@Observable
final class StabilizationAnalyzer {
    static let shared = StabilizationAnalyzer()

    /// 분석 중인 원본(캐시 키)과 진행률(0~1).
    private(set) var progress: [MediaAsset.ID: Double] = [:]
    /// 분석 결과가 생길 때마다 올라간다. 미리보기가 다시 합성할 때를 아는 데 쓴다.
    private(set) var revision = 0
    @ObservationIgnored private var tasks: [MediaAsset.ID: Task<Void, Never>] = [:]

    // MARK: - Queries

    nonisolated static func folder() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Stabilization", directoryHint: .isDirectory)
    }

    /// 저장된 분석 결과. 없으면 `nil`.
    nonisolated static func motionPath(for asset: MediaAsset) -> MotionPath? {
        guard let url = folder()?.appending(path: "\(asset.mediaKey.uuidString).json"),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredMotionPath.self, from: data)
        else { return nil }
        return MotionPath(times: stored.times, x: stored.x, y: stored.y)
    }

    func hasAnalysis(_ asset: MediaAsset) -> Bool {
        _ = revision
        return Self.motionPath(for: asset) != nil
    }

    // MARK: - Commands

    /// 아직 분석하지 않은 영상이면 뒤에서 분석한다. 프록시가 있으면 프록시로 빨리 분석한다(움직임 비율은 같다).
    func analyzeIfNeeded(_ asset: MediaAsset) {
        guard asset.kind == .video, tasks[asset.mediaKey] == nil, Self.motionPath(for: asset) == nil, let folder = Self.folder() else { return }
        let source = ProxyGenerator.previewURL(for: asset)
        let destination = folder.appending(path: "\(asset.mediaKey.uuidString).json")
        progress[asset.mediaKey] = 0
        tasks[asset.mediaKey] = Task {
            // 내보내는 중이면 끝난 뒤에 분석한다(#131).
            await MediaWorkGate.shared.waitUntilIdle()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let path = try await Self.analyze(url: source) { fraction in
                    Task { @MainActor in
                        if self.progress[asset.mediaKey] != nil {
                            self.progress[asset.mediaKey] = fraction
                        }
                    }
                }
                try JSONEncoder().encode(StoredMotionPath(times: path.times, x: path.x, y: path.y)).write(to: destination, options: .atomic)
                revision += 1
            } catch {
                Logger.playback.error("손떨림 분석 실패: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
            }
            progress[asset.mediaKey] = nil
            tasks[asset.mediaKey] = nil
        }
    }

    /// 영상의 프레임마다 누적 움직임(화면 비율, Core Image 좌표 — 오른쪽·위가 양수). 이웃 프레임을 Vision 이동 정합으로 맞춘다.
    nonisolated static func analyze(url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> MotionPath {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SequenceExporter.ExportError.noPicture }
        let (duration, naturalSize) = try await(asset.load(.duration), track.load(.naturalSize))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? SequenceExporter.ExportError.cannotCreateSession }

        var times: [Double] = []
        var x: [Double] = []
        var y: [Double] = []
        var previous: CVPixelBuffer?
        var total = (x: 0.0, y: 0.0)
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let previous {
                // 앞 프레임(떠 있는 이미지)을 지금 프레임(기준)에 맞추는 이동 = 화면 내용이 움직인 만큼.
                let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: previous)
                try VNImageRequestHandler(cvPixelBuffer: buffer).perform([request])
                if let alignment = request.results?.first {
                    total.x += alignment.alignmentTransform.tx / naturalSize.width
                    total.y += alignment.alignmentTransform.ty / naturalSize.height
                }
            }
            times.append(time)
            x.append(total.x)
            y.append(total.y)
            previous = buffer
            if duration.seconds > 0 {
                progress(min(time / duration.seconds, 1))
            }
        }
        if reader.status == .failed {
            throw reader.error ?? SequenceExporter.ExportError.cannotCreateSession
        }
        return MotionPath(times: times, x: x, y: y)
    }
}

private struct StoredMotionPath: Codable {
    let times: [Double]
    let x: [Double]
    let y: [Double]
}
