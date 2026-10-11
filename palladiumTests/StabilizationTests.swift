import AVFoundation
import CoreImage
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 손떨림 보정(#71): 경로 펴기·확대 계산, Vision 분석의 방향, 합성에서 되돌려 옮기기, 편집기·저장.
struct StabilizationTests {
    @Test("일정하게 움직이는 경로는 거의 보정하지 않고, 튀는 프레임은 튄 만큼 되돌리며, 확대는 가장 크게 옮기는 만큼(최대 130%)이다")
    func correctionAndZoom() {
        let times = (0 ..< 90).map { Double($0) / 30 }
        let pan = MotionPath(times: times, x: times.map { $0 * 0.1 }, y: times.map { _ in 0 })
        let panCorrection = pan.correction(at: 1.5, window: 1)
        #expect(abs(panCorrection.x) < 0.001 && panCorrection.y == 0)

        // 짝수 프레임은 0, 홀수 프레임은 0.02로 흔들린다(평균 0.01).
        let jitter = MotionPath(times: times, x: times.indices.map { $0 % 2 == 0 ? 0 : 0.02 }, y: times.map { _ in 0 })
        #expect(abs(jitter.correction(at: times[45], window: 1).x + 0.01) < 0.002)
        #expect(abs(jitter.correction(at: times[44], window: 1).x - 0.01) < 0.002)
        let zoom = jitter.zoom(during: 0 ... 3, window: 1)
        #expect(zoom > 1.01 && zoom < 1.06)

        let wild = MotionPath(times: times, x: times.indices.map { $0 % 2 == 0 ? 0 : 0.6 }, y: times.map { _ in 0 })
        #expect(wild.zoom(during: 0 ... 3, window: 1) == MotionPath.maximumZoom)
        #expect(MotionPath(times: [], x: [], y: []).correction(at: 1, window: 1) == (0, 0))
    }

    @Test("세기는 0~1로 맞추고, 펴는 시간 폭은 세기에 따라 0.3~3초다")
    func settings() {
        var settings = ClipStabilization(strength: 3)
        settings.clamp()
        #expect(settings.strength == 1 && settings.smoothingWindow == 3)
        #expect(ClipStabilization(strength: 0).smoothingWindow == 0.3)
    }

    @Test("분석은 화면 내용이 오른쪽·아래로 움직이면 x는 늘고 y(아래가 음수)는 준다")
    func analyzerDirection() async throws {
        let url = try await Self.makeMovingPatternVideo(frames: 12) { frame in (dx: frame * 4, dy: frame * 3) }
        let path = try await StabilizationAnalyzer.analyze(url: url)
        #expect(path.times.count == 12)
        let lastX = try #require(path.x.last)
        let lastY = try #require(path.y.last)
        // 11프레임 동안 오른쪽 44px(폭 160의 27.5%), 아래 33px(높이 120의 27.5%).
        #expect(abs(lastX - 44.0 / 160) < 0.05)
        #expect(abs(lastY + 33.0 / 120) < 0.05)
    }

    @Test("보정은 튄 프레임을 반대로 옮기고 가운데 기준으로 키운다")
    func applyMovesFrame() throws {
        let width = 1000.0
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: width / 2, height: 500))
            .composited(over: CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: width, height: 500)))
        let clip = try #require(Clip(assetID: UUID(), sourceRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 10)), timelineStart: .zero))
        // 가운데 프레임만 오른쪽으로 10% 튀었다.
        let path = MotionPath(times: [0, 1.0 / 30, 2.0 / 30], x: [0, 0.1, 0], y: [0, 0, 0])
        let layer = StabilizedLayer(path: path, settings: ClipStabilization(strength: 0), clip: clip)
        // 가장 크게 옮기는 만큼(평균과의 차 0.1 × 2/3)을 확대한 화면에서도 덮도록 1 / (1 - 2 × 옮김).
        #expect(abs(layer.zoom - 1 / (1 - 2 * 0.1 * 2 / 3)) < 1e-6)

        let shifted = layer.apply(to: image, at: CMTime(value: 1, timescale: 30))
        #expect(shifted.extent == image.extent)
        let context = CIContext()
        func red(atX x: Double) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(shifted, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: 250, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return pixel[0]
        }
        // 빨강·파랑 경계(원래 500)가 왼쪽으로 옮겨져 450은 파랑, 380은 빨강이다.
        #expect(red(atX: 450) < 50)
        #expect(red(atX: 380) > 200)
    }

    @MainActor
    @Test("편집기는 손떨림 보정을 켜고 끄며, 나눈 조각도 같은 설정이고, 저장했다가 그대로 불러온다")
    func editorAndPersistence() throws {
        let container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.autosaveEnabled = false
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        let editor = ProjectEditor(project: project, repository: repository)
        let clip = try #require(editor.currentSequence.tracks.first?.clips.first)

        editor.setStabilization(ClipStabilization(strength: 0.8), for: clip.id)
        #expect(editor.currentSequence.clip(id: clip.id)?.stabilization?.strength == 0.8)
        #expect(editor.currentSequence.clip(id: clip.id)?.hasEffect == true)
        editor.splitClips([clip.id], at: CMTime(value: 4, timescale: 1))
        #expect(editor.currentSequence.tracks.first?.clips.filter { $0.assetID == clip.assetID }.allSatisfy { $0.stabilization?.strength == 0.8 } == true)
        try editor.save()
        #expect(try repository.project(id: project.id) == editor.project)

        editor.setStabilization(nil, for: clip.id)
        #expect(editor.currentSequence.clip(id: clip.id)?.stabilization == nil)
    }

    /// 무늬(겹치지 않는 네모 격자)가 프레임마다 `offset`만큼 움직이는 160×120 영상. 화면 좌표(아래로 +y)다.
    private static func makeMovingPatternVideo(frames: Int, offset: (Int) -> (dx: Int, dy: Int)) async throws -> URL {
        let width = 160
        let height = 120
        let url = TestMedia.temporaryURL(extension: "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let (dx, dy) = offset(frame)
            for row in 0 ..< height {
                for column in 0 ..< width {
                    // 움직인 좌표에서 본 무늬: 6px 칸마다 해시로 고른 밝기(되풀이되지 않아 정합이 다른 칸에 맞지 않는다).
                    let u = (column - dx + 400) / 6
                    let v = (row - dy + 400) / 6
                    let hash = (u &* 73_856_093) ^ (v &* 19_349_663)
                    let value = UInt8(abs(hash >> 4) % 200 + 40)
                    let offset = row * bytesPerRow + column * 4
                    base[offset] = value
                    base[offset + 1] = UInt8((Int(value) * 3) % 256)
                    base[offset + 2] = 255 - value
                    base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
