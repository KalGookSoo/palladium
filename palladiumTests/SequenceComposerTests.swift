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

    @Test("세로 영상은 가로 화면 가운데에 높이를 맞춰 넣는다")
    func fitsPortraitIntoLandscape() {
        let transform = SequenceComposer.fitTransform(
            naturalSize: CGSize(width: 1080, height: 1920),
            preferredTransform: .identity,
            into: CGSize(width: 1920, height: 1080)
        )
        let fitted = CGRect(x: 0, y: 0, width: 1080, height: 1920).applying(transform)
        #expect(abs(fitted.height - 1080) < 0.5)
        #expect(abs(fitted.midX - 960) < 0.5)
        #expect(abs(fitted.minY) < 0.5)
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
}
