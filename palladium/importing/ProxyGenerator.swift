import AVFoundation
import Observation
import OSLog

/// 고해상도 영상의 프록시(1080p 이하 대체 파일)를 만들고 찾는다(#43). 프록시는 프로젝트에 저장하지 않는 앱 캐시라
/// 앱 컨테이너 Application Support/Proxies/<원본 캐시 키(mediaKey)>.mov에 두고(파생 항목은 처음 원본 것을 같이 쓴다), 파일이 있으면 미리보기가 원본 대신 쓴다.
/// 내보내기는 항상 원본으로 한다.
@Observable
final class ProxyGenerator {
    static let shared = ProxyGenerator()

    /// 만드는 중인 원본(캐시 키 `mediaKey`)과 진행률(0~1).
    private(set) var progress: [MediaAsset.ID: Double] = [:]
    /// 프록시가 생기거나 없어질 때마다 올라간다. 미리보기가 다시 합성할 때를 아는 데 쓴다.
    private(set) var revision = 0
    @ObservationIgnored private var tasks: [MediaAsset.ID: Task<Void, Never>] = [:]

    // MARK: - Queries

    nonisolated static func proxyFolder() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Proxies", directoryHint: .isDirectory)
    }

    /// 다 만든 프록시 파일. 없으면 `nil`.
    nonisolated static func proxyURL(for asset: MediaAsset) -> URL? {
        guard asset.kind == .video, let url = proxyFolder()?.appending(path: "\(asset.mediaKey.uuidString).mov"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// 미리보기에 쓸 파일: 프록시가 있으면 프록시, 없으면 원본.
    static func previewURL(for asset: MediaAsset) -> URL {
        proxyURL(for: asset) ?? MediaFileAccess.resolvedURL(for: asset)
    }

    func hasProxy(_ asset: MediaAsset) -> Bool {
        _ = revision
        return Self.proxyURL(for: asset) != nil
    }

    // MARK: - Commands

    /// 가져온 영상 중 기준 해상도 이상인 것만 프록시를 만든다.
    func generateIfNeeded(for assets: [MediaAsset], threshold: ProxyThreshold) {
        guard threshold != .off else { return }
        for asset in assets where asset.kind == .video {
            Task {
                guard let size = await ClipContentProvider.shared.contentSize(for: asset),
                      threshold.shouldGenerateProxy(pixelSize: size)
                else { return }
                generate(for: asset)
            }
        }
    }

    /// 해상도와 상관없이 프록시를 만든다(미디어 패널 우클릭). 이미 있거나 만드는 중이면 그대로 둔다.
    func generate(for asset: MediaAsset) {
        guard asset.kind == .video, tasks[asset.mediaKey] == nil, Self.proxyURL(for: asset) == nil,
              let folder = Self.proxyFolder()
        else { return }
        let destination = folder.appending(path: "\(asset.mediaKey.uuidString).mov")
        let source = MediaFileAccess.resolvedURL(for: asset)
        progress[asset.mediaKey] = 0
        tasks[asset.mediaKey] = Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Self.makeProxy(from: source, to: destination) { fraction in
                    Task { @MainActor in
                        if self.progress[asset.mediaKey] != nil {
                            self.progress[asset.mediaKey] = fraction
                        }
                    }
                }
                revision += 1
            } catch {
                Logger.mediaImport.error("프록시 생성 실패: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
            }
            progress[asset.mediaKey] = nil
            tasks[asset.mediaKey] = nil
        }
    }

    /// 프록시를 지운다(만드는 중이면 멈춘다). 미리보기는 다시 원본을 쓴다.
    func removeProxy(for asset: MediaAsset) {
        tasks[asset.mediaKey]?.cancel()
        if let url = Self.proxyURL(for: asset) {
            try? FileManager.default.removeItem(at: url)
            revision += 1
        }
    }

    /// 원본을 1080p 이하 H.264로 줄여 쓴다. 길이·시각은 원본과 같다. 실패하거나 취소되면 만들던 파일을 지운다.
    nonisolated static func makeProxy(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw SequenceExporter.ExportError.cannotCreateSession
        }
        // 다 만든 파일만 프록시로 보이도록 임시 이름으로 쓴 뒤 옮긴다.
        let partial = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString).partial.mov")
        let progressTask = Task {
            for await state in session.states(updateInterval: 0.5) {
                if case let .exporting(exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }
        do {
            try await session.export(to: partial, as: .mov)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            Logger.mediaImport.notice("프록시 생성: \(destination.lastPathComponent, privacy: .public)")
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }
}
