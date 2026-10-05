import AVFoundation
import CoreImage
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

    @Test("자막은 모든 층 위에 스타일대로 그리고, 클립보다 늦게 끝나는 자막도 그 시간까지 보인다")
    func drawsSubtitlesOnTop() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let videoID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: videoID)
        let subtitleID = sequence.addSubtitle(at: .zero, text: "■")
        sequence.updateSubtitle(subtitleID, text: "■", style: SubtitleStyle(fontSize: 120, position: .middle, color: .yellow, hasBackground: true))
        let subtitle = try #require(sequence.subtitles.first)

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        #expect(abs(composition.duration.seconds - 3) < 0.01)
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let render = SequenceComposer.renderSize(for: .landscape16x9)
        let box = try #require(SubtitleRenderer.image(for: subtitle, renderSize: render)).extent
        // 상자 왼쪽 여백: 빨간 화면 위의 반투명 검은 배경(Core Image는 선형 공간에서 섞어 생각보다 밝다).
        let backgroundX = (box.minX + 4) / render.width
        let middleY = (render.height - box.midY) / render.height
        let frame = try await generator.image(at: seconds(0.5)).image
        let background = TestMedia.color(of: frame, atX: backgroundX, y: middleY)
        #expect(background.red > 60 && background.red < 190 && background.green < 40)
        let glyph = TestMedia.centerColor(of: frame)
        #expect(glyph.red > 200 && glyph.green > 160 && glyph.blue < 80)
        // 자막 밖은 영상 그대로다.
        let outside = TestMedia.color(of: frame, atX: 0.1, y: 0.1)
        #expect(outside.red > 200 && outside.green < 40)

        // 클립이 끝난 뒤(1~3초)에도 자막만 검은 화면 위에 보인다.
        let late = try await generator.image(at: seconds(2)).image
        let lateGlyph = TestMedia.centerColor(of: late)
        let lateOutside = TestMedia.color(of: late, atX: 0.1, y: 0.1)
        #expect(lateGlyph.red > 200 && lateGlyph.green > 160)
        #expect(lateOutside.red < 30 && lateOutside.green < 30)
    }

    @Test("자막은 위·가운데·아래 위치에 따라 화면 위쪽·가운데·아래쪽에 놓인다")
    func subtitlePositions() throws {
        let render = CGSize(width: 1920, height: 1080)
        func box(_ position: SubtitlePosition) throws -> CGRect {
            let subtitle = Subtitle(
                id: UUID(), range: CMTimeRange(start: .zero, duration: seconds(1)), text: "안녕하세요",
                style: SubtitleStyle(position: position)
            )
            return try #require(SubtitleRenderer.image(for: subtitle, renderSize: render)).extent
        }
        // Core Image 좌표(왼쪽 아래 원점).
        let bottom = try box(.bottom)
        let middle = try box(.middle)
        let top = try box(.top)
        #expect(bottom.minY < 100 && top.maxY > 980)
        #expect(abs(middle.midY - 540) < 1)
        #expect(abs(bottom.midX - 960) < 1)
        #expect(bottom.width < render.width * SubtitleRenderer.maximumWidthRatio)
    }

    /// 빨간 2초 영상 뒤에 파란 2초 영상을 붙이고 파란 클립에 1초 전환을 둔 합성의 프레임 생성기.
    private func transitionGenerator(kind: TransitionKind) async throws -> AVAssetImageGenerator {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 2)
        let blueURL = try await TestMedia.makeVideo(red: 0, green: 0, blue: 255, seconds: 2)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: seconds(2))
        let blue = MediaAsset(id: UUID(), name: "blue.mov", sourceURL: blueURL, kind: .video, duration: seconds(2))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: trackID)
        let blueClip = try #require(blue.makeClip(at: seconds(2)))
        sequence.place(blueClip, onTrack: trackID)
        sequence.setTransition(ClipTransition(kind: kind, duration: seconds(1)), forClip: blueClip.id)

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [red, blue], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        #expect(abs(composition.duration.seconds - 4) < 0.01)
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    @Test("디졸브는 컷 지점을 가운데 두고 앞 클립에서 뒤 클립으로 서서히 바뀐다(원본 여분이 없으면 끝·첫 프레임을 멈춰 쓴다)")
    func dissolveBlendsAcrossCut() async throws {
        let generator = try await transitionGenerator(kind: .dissolve)
        let before = try await TestMedia.centerColor(of: generator.image(at: seconds(1.2)).image)
        let middle = try await TestMedia.centerColor(of: generator.image(at: seconds(2)).image)
        let after = try await TestMedia.centerColor(of: generator.image(at: seconds(2.8)).image)
        #expect(before.red > 200 && before.blue < 60)
        #expect(middle.red > 60 && middle.blue > 60)
        #expect(after.blue > 200 && after.red < 60)
    }

    @Test("와이프는 뒤 클립이 왼쪽부터 밀고 들어온다")
    func wipeRevealsFromLeft() async throws {
        let generator = try await transitionGenerator(kind: .wipe)
        let frame = try await generator.image(at: seconds(2)).image
        let left = TestMedia.color(of: frame, atX: 0.25, y: 0.5)
        let right = TestMedia.color(of: frame, atX: 0.75, y: 0.5)
        #expect(left.blue > 200 && left.red < 60)
        #expect(right.red > 200 && right.blue < 60)
    }

    @Test("오디오 크로스페이드는 컷 지점 앞뒤로 앞 클립 소리를 줄이고 뒤 클립 소리를 키운다")
    func audioCrossfadeRamps() async throws {
        let toneURL = try TestMedia.makeTone(seconds: 2)
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: toneURL, kind: .audio, duration: seconds(2))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .audio)
        try sequence.place(#require(tone.makeClip(at: .zero)), onTrack: trackID)
        let second = try #require(tone.makeClip(at: seconds(2)))
        sequence.place(second, onTrack: trackID)
        sequence.setAudioCrossfade(seconds(1), forClip: second.id)

        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [tone], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let parameters = try #require(composition.audioMix?.inputParameters)
        let rampsAtCut = parameters.map { input -> (Float, Float) in
            var start: Float = -1
            var end: Float = -1
            var range = CMTimeRange()
            _ = input.getVolumeRamp(for: seconds(2), startVolume: &start, endVolume: &end, timeRange: &range)
            return (start, end)
        }
        #expect(rampsAtCut.contains { $0 == (1, 0) })
        #expect(rampsAtCut.contains { $0 == (0, 1) })
    }

    /// 빨강·파랑 반반 이미지 4초 위에 1~3초 동안 마스크를 둔 합성의 프레임 생성기.
    private func maskGenerator(_ mask: Mask) async throws -> AVAssetImageGenerator {
        let splitURL = try TestMedia.makeSplitImage()
        let split = MediaAsset(id: UUID(), name: "split.png", sourceURL: splitURL, kind: .image, duration: MediaAsset.stillImageDuration)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        var clip = try #require(split.makeClip(at: .zero))
        clip.sourceRange = CMTimeRange(start: .zero, duration: seconds(4))
        sequence.place(clip, onTrack: trackID)
        sequence.masks = [mask]
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [split], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    @Test("블러 마스크는 지정한 시간 동안 영역 안만 흐리고, 영역 밖과 다른 시간은 그대로 둔다")
    func blurMaskBlursOnlyArea() async throws {
        let mask = Mask(id: UUID(), range: CMTimeRange(start: seconds(1), duration: seconds(2)), area: MaskArea(width: 0.5, height: 0.5), effect: .blur, strength: 1)
        let generator = try await maskGenerator(mask)
        let masked = try await generator.image(at: seconds(2)).image
        let boundary = TestMedia.color(of: masked, atX: 0.5, y: 0.5)
        let outside = TestMedia.color(of: masked, atX: 0.1, y: 0.5)
        #expect(boundary.red > 50 && boundary.blue > 50)
        #expect(outside.red > 200 && outside.blue < 30)
        let unmasked = try await TestMedia.color(of: generator.image(at: seconds(0.5)).image, atX: 0.49, y: 0.5)
        #expect(unmasked.red > 200 && unmasked.blue < 30)
    }

    @Test("모자이크 마스크는 영역 안을 큰 칸으로 칠해, 경계 양옆이 같은 칸이면 같은 색이 된다")
    func mosaicMaskPixellates() async throws {
        let mask = Mask(id: UUID(), range: CMTimeRange(start: seconds(1), duration: seconds(2)), area: MaskArea(width: 0.5, height: 0.5), effect: .mosaic, strength: 1)
        let generator = try await maskGenerator(mask)
        let frame = try await generator.image(at: seconds(2)).image
        // 칸 크기 약 71px, 영역 왼쪽(480px)부터 칸을 나누므로 950px·970px은 같은 칸이다.
        let left = TestMedia.color(of: frame, atX: 950.0 / 1920, y: 0.5)
        let right = TestMedia.color(of: frame, atX: 970.0 / 1920, y: 0.5)
        #expect(abs(left.red - right.red) < 10 && abs(left.blue - right.blue) < 10)
        let outside = TestMedia.color(of: frame, atX: 0.1, y: 0.5)
        #expect(outside.red > 200 && outside.blue < 30)
    }
}
