import AVFoundation
import CoreMedia
import Foundation
import ImageIO
@testable import palladium
import Testing

struct SequenceExporterTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("시퀀스를 MP4로 내보내면 시퀀스 길이·화면비 크기의 영상과 소리가 담기고, 프레임이 미리보기와 같다")
    func exportsSequence() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let toneURL = try TestMedia.makeTone(seconds: 1)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(1))
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: toneURL, kind: .audio, duration: seconds(1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let videoID = sequence.addTrack(kind: .video)
        let audioID = sequence.addTrack(kind: .audio)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: videoID)
        try sequence.place(#require(tone.makeClip(at: .zero)), onTrack: audioID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red, tone], aspectRatio: .portrait9x16, resolveURL: \.sourceURL
        ))
        let output = TestMedia.temporaryURL(extension: "mp4")
        let lastProgress = LockedValue(0.0)

        try await SequenceExporter.export(composition, to: output) { lastProgress.set($0) }

        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration)
        let videoTrack = try #require(try await exported.loadTracks(withMediaType: .video).first)
        let size = try await videoTrack.load(.naturalSize)
        #expect(abs(duration.seconds - 1) < 0.1)
        #expect(size == CGSize(width: 1080, height: 1920))
        #expect(try await !exported.loadTracks(withMediaType: .audio).isEmpty)
        #expect(lastProgress.get() == 1)

        let generator = AVAssetImageGenerator(asset: exported)
        let center = try await TestMedia.centerColor(of: generator.image(at: seconds(0.5)).image)
        #expect(center.red > 180 && center.blue < 80)
    }

    @Test("전환이 있는 시퀀스도 길이 그대로 내보내고, 컷 지점에서 두 클립이 섞인다")
    func exportsTransition() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let blueURL = try await TestMedia.makeVideo(red: 0, green: 0, blue: 255, seconds: 1)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(1))
        let blue = MediaAsset(id: UUID(), name: "blue.mov", sourceURL: blueURL, kind: .video, duration: seconds(1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: trackID)
        let blueClip = try #require(blue.makeClip(at: seconds(1)))
        sequence.place(blueClip, onTrack: trackID)
        sequence.setTransition(ClipTransition(kind: .dissolve, duration: seconds(0.6)), forClip: blueClip.id)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red, blue], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let output = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: output) { _ in }

        let exported = AVURLAsset(url: output)
        #expect(try await abs(exported.load(.duration).seconds - 2) < 0.1)
        let generator = AVAssetImageGenerator(asset: exported)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let middle = try await TestMedia.centerColor(of: generator.image(at: seconds(1)).image)
        #expect(middle.red > 60 && middle.blue > 60)
    }

    @Test("정지 프레임은 합성 화면 크기의 PNG이고, 미리보기에서 그 시각에 보이던 프레임과 같다")
    func exportsStillFrame() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let blueURL = try await TestMedia.makeVideo(red: 0, green: 0, blue: 255, seconds: 1)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(1))
        let blue = MediaAsset(id: UUID(), name: "blue.mov", sourceURL: blueURL, kind: .video, duration: seconds(1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: trackID)
        try sequence.place(#require(blue.makeClip(at: seconds(1))), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red, blue], aspectRatio: .square1x1, resolveURL: \.sourceURL
        ))
        let output = TestMedia.temporaryURL(extension: "png")

        try await SequenceExporter.exportStillFrame(composition, at: seconds(1.5), to: output)

        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let still = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(still.width == 1080 && still.height == 1080)
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let preview = try await TestMedia.centerColor(of: generator.image(at: seconds(1.5)).image)
        let saved = TestMedia.centerColor(of: still)
        #expect(saved.blue > 200 && saved.red < 60)
        #expect(abs(saved.red - preview.red) <= 2 && abs(saved.blue - preview.blue) <= 2)
    }

    /// 60fps 640×360 영상 하나를 놓은 시퀀스의 합성.
    private func sixtyFPSComposition(resolution: ExportResolution) async throws -> SequenceComposition {
        let url = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1, width: 640, height: 360, fps: 60)
        let asset = MediaAsset(id: UUID(), name: "60fps.mov", sourceURL: url, kind: .video, duration: seconds(1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(asset.makeClip(at: .zero)), onTrack: trackID)
        return try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [asset], aspectRatio: .landscape16x9, resolution: resolution, resolveURL: \.sourceURL
        ))
    }

    @Test("60fps 원본은 60fps로 내보내 프레임이 줄지 않고, '원본과 같게'는 원본 해상도로 내보낸다")
    func exportKeepsSourceFrameRateAndSize() async throws {
        let composition = try await sixtyFPSComposition(resolution: .source)
        #expect(composition.frameDuration == CMTime(value: 1, timescale: 60))
        let output = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: output) { _ in }

        let exported = AVURLAsset(url: output)
        let track = try #require(try await exported.loadTracks(withMediaType: .video).first)
        let (frameRate, size) = try await track.load(.nominalFrameRate, .naturalSize)
        #expect(abs(frameRate - 60) < 1)
        #expect(size == CGSize(width: 640, height: 360))
        let reader = try AVAssetReader(asset: exported)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(readerOutput)
        reader.startReading()
        var frameCount = 0
        while let sample = readerOutput.copyNextSampleBuffer() {
            frameCount += CMSampleBufferGetNumSamples(sample)
        }
        #expect(abs(frameCount - 60) <= 1)
    }

    @Test("프레임 간격이 흔들리는 아이폰식 영상(평균 59.95fps)은 59.94가 아니라 60fps로 내보내 프레임이 줄지 않는다")
    func exportRoundsJitteredFrameRateUp() async throws {
        let url = try await TestMedia.makeVideo(red: 0, green: 0, blue: 255, seconds: 2, width: 640, height: 360, fps: 59.95)
        let asset = MediaAsset(id: UUID(), name: "iphone.mov", sourceURL: url, kind: .video, duration: seconds(2))
        let sourceTrack = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let sourceRate = try await sourceTrack.load(.nominalFrameRate)
        #expect(sourceRate > 59.9 && sourceRate < 60)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(asset.makeClip(at: .zero)), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [asset], aspectRatio: .landscape16x9, resolution: .source, resolveURL: \.sourceURL
        ))
        #expect(composition.frameDuration == CMTime(value: 1, timescale: 60))
        let output = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: output) { _ in }

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await abs(track.load(.nominalFrameRate) - 60) < 0.01)
    }

    @Test("HEVC를 고르면 HEVC로 인코딩하고, 해상도를 고르면 그 크기로 내보낸다")
    func exportUsesChosenCodecAndResolution() async throws {
        let composition = try await sixtyFPSComposition(resolution: .hd720)
        let output = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: output, codec: .hevc) { _ in }

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        let (size, descriptions) = try await track.load(.naturalSize, .formatDescriptions)
        #expect(size == CGSize(width: 1280, height: 720))
        let codecType = try #require(descriptions.first).mediaSubType.rawValue
        #expect(codecType == kCMVideoCodecType_HEVC)
    }

    @Test("화질 단계는 해상도·프레임레이트·코덱으로 비트레이트를 계산하고, 원본과 비슷하게는 원본 데이터율을, 직접 입력은 그 값을 쓰며 1~200Mbit/s로 맞춘다")
    func bitRateRules() {
        let hd = CGSize(width: 1920, height: 1080)
        let thirty = CMTime(value: 1, timescale: 30)
        let sixty = CMTime(value: 1, timescale: 60)
        func mbps(_ quality: ExportQuality, codec: ExportCodec = .h264, size: CGSize = hd, frame: CMTime = thirty, source: Double? = nil, custom: Double = 20) -> Double {
            ExportBitRate.bitsPerSecond(quality: quality, codec: codec, renderSize: size, frameDuration: frame, sourceBitRate: source, customMbps: custom) / 1_000_000
        }
        #expect(abs(mbps(.high) - 9.33) < 0.01)
        #expect(mbps(.high) > mbps(.medium) && mbps(.medium) > mbps(.small))
        #expect(abs(mbps(.high, codec: .hevc) - mbps(.high) * 0.6) < 0.01)
        #expect(abs(mbps(.high, frame: sixty) / mbps(.high) - pow(2, 0.6)) < 0.01)
        #expect(mbps(.source, source: 14_000_000) == 14)
        #expect(mbps(.source) == mbps(.high))
        #expect(mbps(.custom, custom: 35) == 35)
        #expect(mbps(.custom, custom: 0.2) == ExportBitRate.minimumMbps)
        #expect(mbps(.custom, custom: 999) == ExportBitRate.maximumMbps)
        #expect(mbps(.small, size: CGSize(width: 64, height: 36)) == ExportBitRate.minimumMbps)
    }

    @Test("합성은 원본 영상의 데이터율을 알려 주고, 내보내기 비트레이트는 그 값과 고른 화질을 따른다")
    func compositionReportsSourceBitRate() async throws {
        let composition = try await sixtyFPSComposition(resolution: .source)
        let sourceRate = try #require(composition.sourceBitRate)
        #expect(sourceRate > 0)
        #expect(SequenceExporter.videoBitRate(for: composition, codec: .h264, quality: .source, customMbps: 20) == max(sourceRate, ExportBitRate.minimumMbps * 1_000_000))
        #expect(SequenceExporter.videoBitRate(for: composition, codec: .h264, quality: .custom, customMbps: 12) == 12_000_000)
    }

    @Test("직접 입력한 높은 비트레이트로 내보내면 낮은 비트레이트보다 데이터율이 높다")
    func exportFollowsBitRate() async throws {
        // 움직임이 있어야 인코더가 비트레이트를 채우므로 샘플 영상(움직이는 원·글자)을 쓴다.
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = directory.appending(path: "sample.mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await SampleMediaGenerator.makeVideo(SampleMediaGenerator.videos[0], to: url)
        let asset = MediaAsset(id: UUID(), name: "sample.mov", sourceURL: url, kind: .video, duration: seconds(6))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(asset.makeClip(at: .zero)), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [asset], aspectRatio: .landscape16x9, resolution: .source, resolveURL: \.sourceURL
        ))
        let low = TestMedia.temporaryURL(extension: "mp4")
        let high = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: low, quality: .custom, customMbps: 1) { _ in }
        try await SequenceExporter.export(composition, to: high, quality: .custom, customMbps: 30) { _ in }

        let lowSize = try #require(try FileManager.default.attributesOfItem(atPath: low.path)[.size] as? Int)
        let highSize = try #require(try FileManager.default.attributesOfItem(atPath: high.path)[.size] as? Int)
        #expect(highSize > lowSize)
    }

    @Test("내보내기를 취소하면 취소 오류로 끝나고 만들던 파일을 지운다")
    func cancelRemovesFile() async throws {
        let url = try await TestMedia.makeVideo(red: 0, green: 255, blue: 0, seconds: 20, width: 640, height: 360)
        let asset = MediaAsset(id: UUID(), name: "long.mov", sourceURL: url, kind: .video, duration: seconds(20))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(asset.makeClip(at: .zero)), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [asset], aspectRatio: .landscape16x9, resolution: .uhd, resolveURL: \.sourceURL
        ))
        let output = TestMedia.temporaryURL(extension: "mp4")

        let task = Task { try await SequenceExporter.export(composition, to: output) { _ in } }
        try await Task.sleep(for: .milliseconds(300))
        #expect(await MediaWorkGate.shared.isExporting)
        let cancelledAt = ContinuousClock.now
        task.cancel()
        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        // 취소는 읽기를 바로 끊어 곧 끝나야 한다(#131 — 0%에서 멈춘 채 취소가 먹지 않았다).
        #expect(ContinuousClock.now - cancelledAt < .seconds(3))
    }

    @Test("자막만 있는 시퀀스도 자막 길이만큼 내보내고 자막이 화면에 박힌다")
    func exportsSubtitleOnlySequence() async throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let subtitleID = sequence.addSubtitle(at: .zero, text: "■")
        sequence.updateSubtitle(subtitleID, text: "■", style: SubtitleStyle(fontSize: 120, centerY: 0.5, textColor: .yellow, backgroundOpacity: 0))
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [], aspectRatio: .square1x1, resolveURL: \.sourceURL
        ))
        let output = TestMedia.temporaryURL(extension: "mp4")

        try await SequenceExporter.export(composition, to: output) { _ in }

        let exported = AVURLAsset(url: output)
        #expect(try await abs(exported.load(.duration).seconds - 3) < 0.1)
        let center = try await TestMedia.centerColor(of: AVAssetImageGenerator(asset: exported).image(at: seconds(1.5)).image)
        #expect(center.red > 180 && center.green > 150 && center.blue < 90)
    }
}

/// 배치 내보내기 큐(#6 2단계).
@MainActor
struct BatchExportJobTests {
    private struct FakeFailure: Error, LocalizedError {
        var errorDescription: String? {
            "디스크가 가득 찼습니다"
        }
    }

    @Test("배치 내보내기는 순서대로 처리하고, 하나가 실패해도 나머지를 계속한다")
    func continuesAfterFailure() async {
        let folder = URL(filePath: "/tmp/out")
        let job = BatchExportJob(items: (0 ..< 3).map { index in
            BatchExportJob.Item(sequenceID: UUID(), destination: folder.appending(path: "\(index).mp4"))
        })
        var order: [String] = []

        await job.run { item, progress in
            order.append(item.destination.lastPathComponent)
            progress(0.5)
            if item.destination.lastPathComponent == "1.mp4" {
                throw FakeFailure()
            }
        }

        #expect(order == ["0.mp4", "1.mp4", "2.mp4"])
        #expect(job.items.map(\.state) == [.finished, .failed("디스크가 가득 찼습니다"), .finished])
        #expect(job.isFinished)
    }

    @Test("취소하면 진행 중인 항목과 남은 항목이 취소된다")
    func cancellationStopsRemainingItems() async {
        let job = BatchExportJob(items: (0 ..< 3).map { _ in BatchExportJob.Item(sequenceID: UUID(), destination: URL(filePath: "/tmp/x.mp4")) })
        await job.run { _, _ in throw CancellationError() }
        #expect(job.items.first?.state == .cancelled)

        let cancelledJob = BatchExportJob(items: (0 ..< 2).map { _ in BatchExportJob.Item(sequenceID: UUID(), destination: URL(filePath: "/tmp/y.mp4")) })
        let task = Task { await cancelledJob.run { _, _ in } }
        task.cancel()
        await task.value
        #expect(cancelledJob.items.map(\.state) == [.cancelled, .cancelled])
    }

    @Test("파일 이름은 쓸 수 없는 글자를 바꾸고, 겹치거나 이미 있으면 번호를 붙인다")
    func destinationNames() {
        let folder = URL(filePath: "/tmp/out")
        let urls = BatchExportJob.destinations(for: ["여행/하이라이트", "통합본", "통합본", " "], in: folder) { url in
            url.lastPathComponent == "통합본.mp4"
        }
        #expect(urls.map(\.lastPathComponent) == ["여행-하이라이트.mp4", "통합본 2.mp4", "통합본 3.mp4", "시퀀스.mp4"])
    }
}

/// 내보내기 진행률 콜백(다른 스레드)에서 쓰는 값.
final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}
