import AVFoundation
import CoreMedia
import Foundation
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

    @Test("자막만 있는 시퀀스도 자막 길이만큼 내보내고 자막이 화면에 박힌다")
    func exportsSubtitleOnlySequence() async throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let subtitleID = sequence.addSubtitle(at: .zero, text: "■")
        sequence.updateSubtitle(subtitleID, text: "■", style: SubtitleStyle(fontSize: 120, position: .middle, color: .yellow, hasBackground: false))
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
