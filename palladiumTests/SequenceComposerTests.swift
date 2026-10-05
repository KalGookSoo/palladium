import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import Testing

struct SequenceComposerTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("화면비 프리셋마다 짧은 변이 1080인 출력 크기를 쓴다")
    func renderSizes() {
        #expect(SequenceComposer.renderSize(for: .landscape16x9) == CGSize(width: 1920, height: 1080))
        #expect(SequenceComposer.renderSize(for: .portrait9x16) == CGSize(width: 1080, height: 1920))
        #expect(SequenceComposer.renderSize(for: .square1x1) == CGSize(width: 1080, height: 1080))
    }

    @Test("기본 트랜스폼은 세로 영상을 가로 화면 가운데에 높이를 맞춰 넣고, 배율·위치를 바꾸면 그만큼 옮긴다")
    func transformFrames() {
        let render = CGSize(width: 1920, height: 1080)
        let fitted = ClipTransform().frame(contentSize: CGSize(width: 1080, height: 1920), in: render)
        #expect(abs(fitted.height - 1080) < 0.5)
        #expect(abs(fitted.midX - 960) < 0.5)

        let logo = ClipTransform(centerX: 0.9, centerY: 0.1, scale: 0.2).frame(contentSize: CGSize(width: 100, height: 100), in: render)
        #expect(abs(logo.width - 216) < 0.5)
        #expect(abs(logo.midX - 1728) < 0.5)
        #expect(abs(logo.midY - 108) < 0.5)
    }

    @Test("영상 프레임 변환은 회전 없는 원본을 화면 사각형에 그대로 옮긴다(Core Image 좌표)")
    func videoTransformMapsCorners() {
        let render = CGSize(width: 1920, height: 1080)
        let transform = LayerCompositor.videoTransform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            clipTransform: ClipTransform(centerX: 0.25, centerY: 0.25, scale: 0.5),
            renderSize: render
        )
        let mapped = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080)).applying(transform)
        // 왼쪽 위 사분면(왼쪽 위 원점)은 Core Image에서 왼쪽 위(세로 540~1080)가 된다.
        #expect(abs(mapped.minX) < 0.5 && abs(mapped.maxX - 960) < 0.5)
        #expect(abs(mapped.minY - 540) < 0.5 && abs(mapped.maxY - 1080) < 0.5)
    }

    @Test("메인 영상 트랙의 클립을 시간 순서대로 합성하고, 빈 구간은 검은 화면이며, 오디오 트랙도 함께 넣는다")
    func composesMainTrackAndAudio() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let blueURL = try await TestMedia.makeVideo(red: 0, green: 0, blue: 255, seconds: 1)
        let toneURL = try TestMedia.makeTone(seconds: 3)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(1))
        let blue = MediaAsset(id: UUID(), name: "blue.mov", sourceURL: blueURL, kind: .video, duration: seconds(1))
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: toneURL, kind: .audio, duration: seconds(3))

        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let videoTrackID = sequence.addTrack(kind: .video)
        let audioTrackID = sequence.addTrack(kind: .audio)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: videoTrackID)
        // 1초~2초는 비워 두고 2초에 파란 클립을 둔다.
        try sequence.place(#require(blue.makeClip(at: seconds(2))), onTrack: videoTrackID)
        try sequence.place(#require(tone.makeClip(at: .zero)), onTrack: audioTrackID)

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence,
            assets: [red, blue, tone],
            aspectRatio: .landscape16x9,
            resolveURL: \.sourceURL
        ))

        #expect(abs(composition.duration.seconds - 3) < 0.01)
        #expect(composition.asset.tracks(withMediaType: .video).count == 1)
        #expect(composition.asset.tracks(withMediaType: .audio).count == 1)

        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await TestMedia.centerColor(of: generator.image(at: seconds(0.5)).image)
        let gap = try await TestMedia.centerColor(of: generator.image(at: seconds(1.5)).image)
        let last = try await TestMedia.centerColor(of: generator.image(at: seconds(2.5)).image)
        #expect(first.red > 200 && first.blue < 60)
        #expect(gap.red < 30 && gap.green < 30 && gap.blue < 30)
        #expect(last.blue > 200 && last.red < 60)
    }

    @Test("클립이 없으면 합성하지 않는다")
    func emptySequenceHasNoComposition() async {
        let composition = await SequenceComposer.makeComposition(
            sequence: EditSequence(id: UUID(), name: "빈 시퀀스", tracks: []),
            assets: [],
            aspectRatio: .landscape16x9,
            resolveURL: \.sourceURL
        )
        #expect(composition == nil)
    }

    @Test("위쪽 영상 트랙의 이미지는 메인 영상 위에 지정한 위치·크기로 겹쳐 그리고, 불투명도를 반영한다")
    func overlaysImageOnTopTrack() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 2)
        let blueImageURL = try TestMedia.makeImage(red: 0, green: 0, blue: 255)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(2))
        let logo = MediaAsset(id: UUID(), name: "logo.png", sourceURL: blueImageURL, kind: .image, duration: MediaAsset.stillImageDuration)

        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let mainID = sequence.addTrack(kind: .video)
        let overlayID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: mainID)
        var overlay = try #require(logo.makeClip(at: .zero))
        overlay.sourceRange = CMTimeRange(start: .zero, duration: seconds(1))
        // 화면 왼쪽 위 사분면에 작게.
        overlay.transform = ClipTransform(centerX: 0.25, centerY: 0.25, scale: 0.3)
        sequence.place(overlay, onTrack: overlayID)

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red, logo], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frame = try await generator.image(at: seconds(0.5)).image
        let logoSpot = TestMedia.color(of: frame, atX: 0.25, y: 0.25)
        let elsewhere = TestMedia.color(of: frame, atX: 0.75, y: 0.75)
        #expect(logoSpot.blue > 200 && logoSpot.red < 60)
        #expect(elsewhere.red > 200 && elsewhere.blue < 60)

        // 이미지 클립이 끝난 뒤에는 메인 영상만 보인다.
        let after = try await TestMedia.color(of: generator.image(at: seconds(1.5)).image, atX: 0.25, y: 0.25)
        #expect(after.red > 200 && after.blue < 60)
    }

    @Test("클립 음량과 트랙 음소거를 오디오 믹스에 반영한다")
    func audioMixReflectsVolumes() async throws {
        let toneURL = try TestMedia.makeTone(seconds: 2)
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: toneURL, kind: .audio, duration: seconds(2))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let loudID = sequence.addTrack(kind: .audio)
        let mutedID = sequence.addTrack(kind: .audio)
        var quiet = try #require(tone.makeClip(at: .zero))
        quiet.volume = 0.25
        sequence.place(quiet, onTrack: loudID)
        try sequence.place(#require(tone.makeClip(at: .zero)), onTrack: mutedID)
        sequence.tracks[1].isMuted = true

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [tone], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let parameters = try #require(composition.audioMix?.inputParameters)
        let volumes = parameters.map { input -> Float in
            var start: Float = -1
            var end: Float = -1
            var range = CMTimeRange()
            _ = input.getVolumeRamp(for: seconds(0.5), startVolume: &start, endVolume: &end, timeRange: &range)
            return start
        }
        #expect(volumes.sorted() == [0, 0.25])
    }
}
