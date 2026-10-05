import CoreMedia
import Foundation
@testable import palladium
import Testing

struct TimelineEditingTests {
    private let assetID = UUID()

    @Test("클립 앞쪽 절반에 넣으면 그 클립 앞 경계에 들어가고 뒤 클립이 밀리며, 기존 클립은 나뉘지 않는다")
    func insertGoesToBoundaryBefore() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 4), clip(at: 4, length: 4)])

        try track.insert(clip(at: 1, length: 3))

        #expect(spans(of: track) == [[0, 3], [3, 7], [7, 11]])
        #expect(track.clips.allSatisfy { $0.sourceRange.start == .zero })
    }

    @Test("클립 뒤쪽 절반에 넣으면 그 클립 뒤 경계에 들어간다")
    func insertGoesToBoundaryAfter() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 4), clip(at: 4, length: 4)])

        try track.insert(clip(at: 3, length: 2))

        #expect(spans(of: track) == [[0, 4], [4, 6], [6, 10]])
    }

    @Test("틈에 넣으면 그 시각에 놓고, 뒤 클립과 겹치는 만큼만 민다")
    func insertIntoGapPushesOnlyOverlap() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 2), clip(at: 5, length: 2)])

        try track.insert(clip(at: 3, length: 1))
        #expect(spans(of: track) == [[0, 2], [3, 4], [5, 7]])

        try track.insert(clip(at: 4, length: 2))
        #expect(spans(of: track) == [[0, 2], [3, 4], [4, 6], [6, 8]])
    }

    @Test("새 영상 트랙은 기존 영상 트랙 앞에, 새 오디오 트랙은 맨 뒤에 추가된다")
    func addTrackOrder() {
        var sequence = SampleData.mainSequence
        let videoID = sequence.addTrack(kind: .video)
        let audioID = sequence.addTrack(kind: .audio)

        #expect(sequence.tracks.first?.id == videoID)
        #expect(sequence.tracks.last?.id == audioID)
    }

    @Test("옮기는 클립의 앞 끝이나 뒤 끝이 가까운 경계·재생 헤드·0초에 붙고, 허용 범위 밖이면 그대로 둔다")
    func magneticSnapping() throws {
        let sequence = try sequence(withClipsAt: [(2, 3)])
        let tolerance = seconds(0.3)
        let length = seconds(1)

        // 앞 끝이 5초(클립 뒤 끝)에 붙는다.
        #expect(sequence.snappedStart(seconds(4.8), duration: length, tolerance: tolerance) == seconds(5))
        // 뒤 끝이 2초(클립 앞 끝)에 붙어 시작은 1초가 된다.
        #expect(sequence.snappedStart(seconds(1.2), duration: length, tolerance: tolerance) == seconds(1))
        #expect(sequence.snappedStart(seconds(0.2), duration: length, tolerance: tolerance) == .zero)
        #expect(sequence.snappedStart(seconds(7.9), duration: length, tolerance: tolerance, extraEdges: [seconds(8)]) == seconds(8))
        #expect(sequence.snappedStart(seconds(7), duration: length, tolerance: tolerance) == seconds(7))
    }

    @Test("빈 트랙만 지우고, 놓은 행에서 가장 가까운 같은 종류의 트랙을 찾는다")
    func trackRemovalAndNearestTrack() throws {
        var sequence = try sequence(withClipsAt: [(0, 2)])
        let mainVideoID = sequence.tracks[0].id
        let overlayID = sequence.addTrack(kind: .video)
        let audioID = sequence.addTrack(kind: .audio)

        // 행 순서: 영상 2(0), 영상 1(1), 오디오 1(2)
        #expect(sequence.nearestTrackID(kind: .video, toRow: 5) == mainVideoID)
        #expect(sequence.nearestTrackID(kind: .video, toRow: -1) == overlayID)
        #expect(sequence.nearestTrackID(kind: .audio, toRow: 0) == audioID)

        sequence.removeTrack(mainVideoID)
        sequence.removeTrack(overlayID)
        #expect(sequence.tracks.map(\.id) == [mainVideoID, audioID])
    }

    @Test("이미지는 영상 트랙에 정해진 길이로, 오디오는 오디오 트랙에 원본 길이로 놓인다")
    func placementDefaults() {
        let image = MediaAsset(id: UUID(), name: "logo.png", sourceURL: URL(filePath: "/logo.png"), kind: .image, duration: .zero)
        #expect(image.trackKind == .video)
        #expect(image.placementDuration == MediaAsset.stillImageDuration)
        #expect(SampleData.backgroundMusic.trackKind == .audio)
        #expect(SampleData.backgroundMusic.placementDuration == SampleData.backgroundMusic.duration)
    }

    @Test("삭제는 자리를 비우고, 리플 삭제는 뒤 클립을 당겨 틈을 메운다")
    func removeAndRippleRemove() throws {
        var sequence = try sequence(withClipsAt: [(0, 2), (2, 3), (5, 2)])
        let middleID = sequence.tracks[0].clips[1].id
        var rippled = sequence

        sequence.removeClips([middleID], ripple: false)
        rippled.removeClips([middleID], ripple: true)

        #expect(spans(of: sequence.tracks[0]) == [[0, 2], [5, 7]])
        #expect(spans(of: rippled.tracks[0]) == [[0, 2], [2, 4]])
    }

    @Test("재생 헤드에서 자르면 걸친 클립이 둘로 나뉘고, 고른 클립이 있으면 그 클립만 나뉜다")
    func splitAtPlayhead() throws {
        var sequence = try sequence(withClipsAt: [(0, 4)])
        let otherTrackID = sequence.addTrack(kind: .audio)
        try sequence.place(clip(at: 0, length: 4), onTrack: otherTrackID)
        var onlySelected = sequence

        sequence.split(at: seconds(1), clipIDs: nil)
        onlySelected.split(at: seconds(1), clipIDs: [onlySelected.tracks[0].clips[0].id])

        #expect(sequence.tracks.map { spans(of: $0) } == [[[0, 1], [1, 4]], [[0, 1], [1, 4]]])
        #expect(onlySelected.tracks.map { spans(of: $0) } == [[[0, 1], [1, 4]], [[0, 4]]])
        #expect(sequence.tracks[0].clips[1].sourceRange.start.seconds == 1)
        #expect(sequence.canSplit(at: seconds(2), clipIDs: nil))
        #expect(!sequence.canSplit(at: .zero, clipIDs: nil))
    }

    @Test("옮기면 원래 자리를 메우고 새 자리 경계에 들어가 뒤를 밀어 순서가 바뀐다")
    func moveReorders() throws {
        var sequence = try sequence(withClipsAt: [(0, 2), (2, 3), (5, 1)])
        let first = sequence.tracks[0].clips[0]
        let trackID = sequence.tracks[0].id

        // 맨 앞 클립을 세 번째 클립 앞(화면 기준 5초)으로 옮긴다.
        sequence.moveClip(first.id, toTrack: trackID, at: seconds(5))

        #expect(spans(of: sequence.tracks[0]) == [[0, 3], [3, 5], [5, 6]])
        #expect(sequence.tracks[0].clips[1].id == first.id)
    }

    @Test("종류가 다른 트랙으로는 옮기지 않는다")
    func moveRejectsOtherKind() throws {
        var sequence = try sequence(withClipsAt: [(0, 2)])
        let clipID = sequence.tracks[0].clips[0].id
        let audioTrackID = sequence.addTrack(kind: .audio)

        sequence.moveClip(clipID, toTrack: audioTrackID, at: .zero)

        #expect(sequence.trackID(containing: clipID) == sequence.tracks[0].id)
    }

    // MARK: - Helpers

    private func sequence(withClipsAt spans: [(Double, Double)]) throws -> EditSequence {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        for (start, length) in spans {
            try sequence.place(clip(at: start, length: length), onTrack: trackID)
        }
        return sequence
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    private func clip(at start: Double, length: Double) throws -> Clip {
        try #require(Clip(assetID: assetID, sourceRange: CMTimeRange(start: .zero, duration: seconds(length)), timelineStart: seconds(start)))
    }

    private func spans(of track: Track) -> [[Double]] {
        track.clips.map { [$0.timelineStart.seconds, $0.timelineRange.end.seconds] }
    }
}

struct MarkerCommandTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("마커는 시각 순으로 쌓이고, 이름이 비면 '마커 N'이며, 이름 변경·삭제가 된다")
    func markerCommands() {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let later = sequence.addMarker(at: seconds(5))
        let earlier = sequence.addMarker(at: seconds(2), named: " 인트로 끝 ")

        #expect(sequence.markers.map(\.id) == [earlier, later])
        #expect(sequence.markers.map(\.name) == ["인트로 끝", "마커 1"])

        sequence.renameMarker(later, to: "후렴")
        sequence.renameMarker(later, to: "  ")
        sequence.removeMarker(earlier)
        #expect(sequence.markers.map(\.name) == ["후렴"])
    }
}

struct SubtitleTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("자막은 기본 3초로 시각 순으로 쌓이고, 시간 조정은 0 이전·최소 길이 미만으로 줄지 않으며, 글자 크기는 범위로 맞춘다")
    func subtitleCommands() throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let later = sequence.addSubtitle(at: seconds(5), text: "둘째")
        let earlier = sequence.addSubtitle(at: seconds(1))
        #expect(sequence.subtitles.map(\.id) == [earlier, later])
        #expect(sequence.subtitles.first?.text == "자막")
        #expect(sequence.duration == seconds(8))

        sequence.setSubtitleRange(later, start: seconds(-2), end: seconds(-1))
        let moved = try #require(sequence.subtitles.first { $0.id == later })
        #expect(moved.range.start == .zero)
        #expect(moved.range.duration == Subtitle.minimumDuration)
        #expect(sequence.subtitles.map(\.id) == [later, earlier])

        sequence.updateSubtitle(earlier, text: "첫째\n둘째 줄", style: SubtitleStyle(fontSize: 500))
        let edited = try #require(sequence.subtitles.first { $0.id == earlier })
        #expect(edited.text == "첫째\n둘째 줄")
        #expect(edited.style.fontSize == SubtitleStyle.fontSizeRange.upperBound)

        sequence.removeSubtitle(later)
        #expect(sequence.subtitles.map(\.id) == [earlier])
    }

    @Test("SRT를 읽고 쓰면 시간과 여러 줄 글자가 그대로이고, 형식이 틀린 항목은 건너뛴다")
    func srtRoundTrip() throws {
        let source = "\u{FEFF}1\r\n00:00:01,500 --> 00:00:03,000\r\n안녕하세요\r\n두 번째 줄\r\n\r\n2\r\n잘못된 시간\r\n무시\r\n\r\n3\r\n01:02:03.040 --> 01:02:05,000 X1:0\r\n끝\r\n"
        let parsed = SubtitleFile.parseSRT(source)
        #expect(parsed.map(\.text) == ["안녕하세요\n두 번째 줄", "끝"])
        #expect(parsed.first?.range.start.seconds == 1.5)
        #expect(parsed.first?.range.end.seconds == 3)
        #expect(parsed.last?.range.start.seconds == 3723.04)

        let written = SubtitleFile.makeSRT(parsed)
        #expect(written.hasPrefix("1\n00:00:01,500 --> 00:00:03,000\n안녕하세요\n두 번째 줄\n\n2\n01:02:03,040 --> 01:02:05,000\n끝\n"))
        #expect(SubtitleFile.parseSRT(written).map(\.range) == parsed.map(\.range))
    }
}

struct TransitionTests {
    private let assetID = UUID()

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    private func clip(start: Double, duration: Double) throws -> Clip {
        try #require(Clip(assetID: assetID, sourceRange: CMTimeRange(start: .zero, duration: seconds(duration)), timelineStart: seconds(start)))
    }

    @Test("전환은 앞에 맞닿은 클립이 있을 때만 두고, 길이는 두 클립 중 짧은 쪽을 넘지 않으며, 트림하면 그만큼 줄어든다")
    func transitionRules() throws {
        let first = try clip(start: 0, duration: 2)
        let second = try clip(start: 2, duration: 4)
        let apart = try clip(start: 7, duration: 2)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [Track(id: UUID(), kind: .video, clips: [first, second, apart])])

        sequence.setTransition(ClipTransition(kind: .wipe, duration: seconds(10)), forClip: second.id)
        sequence.setTransition(ClipTransition(kind: .dissolve, duration: seconds(1)), forClip: apart.id)
        sequence.setAudioCrossfade(seconds(0.01), forClip: second.id)
        let track = sequence.tracks[0]
        let placed = try #require(sequence.clip(id: second.id))
        #expect(placed.transitionIn == ClipTransition(kind: .wipe, duration: seconds(2)))
        #expect(placed.audioCrossfadeIn == ClipTransition.minimumDuration)
        #expect(sequence.clip(id: apart.id)?.transitionIn == nil)
        #expect(track.effectiveTransition(into: first) == nil)

        // 앞 클립을 1초로 줄이면 전환도 1초가 된다(저장값은 그대로 두고 그릴 때 줄인다).
        sequence.setSourceRange(CMTimeRange(start: .zero, duration: seconds(1)), forClip: first.id)
        let trimmed = try #require(sequence.clip(id: second.id))
        #expect(sequence.tracks[0].effectiveTransition(into: trimmed)?.duration == seconds(1))

        sequence.setTransition(nil, forClip: second.id)
        #expect(sequence.clip(id: second.id)?.transitionIn == nil)
    }

    @Test("전환이 있는 클립을 나누면 앞 조각만 전환을 갖는다")
    func splitKeepsTransitionOnFirstPart() throws {
        let first = try clip(start: 0, duration: 2)
        let second = try clip(start: 2, duration: 4)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [Track(id: UUID(), kind: .video, clips: [first, second])])
        sequence.setTransition(ClipTransition(kind: .dissolve, duration: seconds(1)), forClip: second.id)

        sequence.split(at: seconds(4), clipIDs: [second.id])

        let parts = sequence.tracks[0].clips.filter { $0.timelineStart >= seconds(2) }.sorted { $0.timelineStart < $1.timelineStart }
        #expect(parts.count == 2)
        #expect(parts.first?.transitionIn != nil)
        #expect(parts.last?.transitionIn == nil)
    }
}

struct MaskTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("마스크는 시각 순으로 쌓이고, 영역·세기는 범위로 맞추며, 시간은 0 이전·최소 길이 미만이 되지 않는다")
    func maskCommands() throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let later = sequence.addMask(at: seconds(4))
        let earlier = sequence.addMask(at: seconds(-1))
        #expect(sequence.masks.map(\.id) == [earlier, later])
        #expect(sequence.masks.first?.range.start == .zero)
        #expect(sequence.duration == .zero)

        var edited = try #require(sequence.masks.first { $0.id == later })
        edited.area = MaskArea(centerX: 2, centerY: -1, width: 0, height: 5)
        edited.strength = 3
        edited.effect = .mosaic
        edited.range = CMTimeRange(start: seconds(100), duration: seconds(1))
        sequence.updateMask(edited)
        let updated = try #require(sequence.masks.first { $0.id == later })
        #expect(updated.area == MaskArea(centerX: 1, centerY: 0, width: MaskArea.sizeRange.lowerBound, height: 1))
        #expect(updated.strength == 1)
        #expect(updated.effect == .mosaic)
        #expect(updated.range.start == seconds(4))

        sequence.setMaskRange(later, start: seconds(1), end: seconds(0.5))
        #expect(sequence.masks.first { $0.id == later }?.range.duration == Mask.minimumDuration)
        sequence.removeMask(earlier)
        #expect(sequence.masks.map(\.id) == [later])
    }
}

struct AdvancedTrimTests {
    private let longAsset = UUID()
    private let stillAsset = UUID()

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    /// 원본 10초짜리 영상 세 클립: A(원본 0~4, 타임라인 0~4), B(원본 2~5, 4~7), C(원본 0~2, 7~9).
    private func makeTrack() throws -> (Track, a: Clip, b: Clip, c: Clip) {
        let a = try #require(Clip(assetID: longAsset, sourceRange: CMTimeRange(start: .zero, duration: seconds(4)), timelineStart: .zero))
        let b = try #require(Clip(assetID: longAsset, sourceRange: CMTimeRange(start: seconds(2), duration: seconds(3)), timelineStart: seconds(4)))
        let c = try #require(Clip(assetID: longAsset, sourceRange: CMTimeRange(start: .zero, duration: seconds(2)), timelineStart: seconds(7)))
        return (Track(id: UUID(), kind: .video, clips: [a, b, c]), a, b, c)
    }

    private func sourceDuration(_ assetID: MediaAsset.ID) -> CMTime? {
        assetID == stillAsset ? nil : CMTime(seconds: 10, preferredTimescale: standardTimescale)
    }

    private func clip(_ id: Clip.ID, in track: Track) throws -> Clip {
        try #require(track.clips.first { $0.id == id })
    }

    @Test("롤은 맞닿은 두 클립의 경계만 옮기고 전체 길이는 그대로이며, 원본 범위·최소 길이를 넘지 않는다")
    func roll() throws {
        var (track, a, b, c) = try makeTrack()
        track.roll(a.id, edge: .end, by: seconds(1), sourceDuration: sourceDuration)
        #expect(try clip(a.id, in: track).sourceRange == CMTimeRange(start: .zero, duration: seconds(5)))
        #expect(try clip(b.id, in: track).sourceRange == CMTimeRange(start: seconds(3), duration: seconds(2)))
        #expect(try clip(b.id, in: track).timelineStart == seconds(5))
        #expect(try clip(c.id, in: track).timelineRange.end == seconds(9))

        // B가 최소 길이만 남을 때까지만 오른쪽으로 간다.
        track.roll(b.id, edge: .start, by: seconds(10), sourceDuration: sourceDuration)
        #expect(try clip(b.id, in: track).sourceRange.duration == Clip.minimumDuration)
        // 왼쪽으로는 B의 원본 시작(0)까지만 간다.
        track.roll(b.id, edge: .start, by: seconds(-100), sourceDuration: sourceDuration)
        #expect(try clip(b.id, in: track).sourceRange.start == .zero)
        #expect(try clip(c.id, in: track).timelineRange.end == seconds(9))

        // 맞닿은 클립이 없는 끝은 바꾸지 않는다.
        let before = track
        track.roll(c.id, edge: .end, by: seconds(1), sourceDuration: sourceDuration)
        #expect(track == before)
    }

    @Test("슬립은 위치·길이는 두고 원본 구간만 옮기며 원본 범위 안에 머문다. 이미지는 바꾸지 않는다")
    func slip() throws {
        var (track, _, b, _) = try makeTrack()
        track.slip(b.id, by: seconds(10), sourceDuration: seconds(10))
        #expect(try clip(b.id, in: track).sourceRange == CMTimeRange(start: seconds(7), duration: seconds(3)))
        track.slip(b.id, by: seconds(-100), sourceDuration: seconds(10))
        #expect(try clip(b.id, in: track).sourceRange == CMTimeRange(start: .zero, duration: seconds(3)))
        #expect(try clip(b.id, in: track).timelineStart == seconds(4))

        let before = track
        track.slip(b.id, by: seconds(1), sourceDuration: nil)
        #expect(track == before)
    }

    @Test("슬라이드는 클립을 옮기며 맞닿은 앞 클립 끝과 뒤 클립 시작을 함께 바꾸고, 전체 길이는 그대로다")
    func slide() throws {
        var (track, a, b, c) = try makeTrack()
        track.slide(b.id, by: seconds(1), sourceDuration: sourceDuration)
        #expect(try clip(a.id, in: track).sourceRange.duration == seconds(5))
        #expect(try clip(b.id, in: track).timelineStart == seconds(5))
        #expect(try clip(b.id, in: track).sourceRange == CMTimeRange(start: seconds(2), duration: seconds(3)))
        #expect(try clip(c.id, in: track).sourceRange == CMTimeRange(start: seconds(1), duration: seconds(1)))
        #expect(try clip(c.id, in: track).timelineRange.end == seconds(9))

        // 뒤 클립 C가 최소 길이가 될 때까지만 오른쪽으로 간다.
        track.slide(b.id, by: seconds(5), sourceDuration: sourceDuration)
        #expect(try clip(c.id, in: track).sourceRange.duration == Clip.minimumDuration)
    }

    @Test("맞닿은 이웃이 없는 쪽으로는 틈 안에서만 슬라이드한다")
    func slideWithinGap() throws {
        let lone = try #require(Clip(assetID: longAsset, sourceRange: CMTimeRange(start: .zero, duration: seconds(2)), timelineStart: seconds(3)))
        let after = try #require(Clip(assetID: longAsset, sourceRange: CMTimeRange(start: .zero, duration: seconds(2)), timelineStart: seconds(6)))
        var track = Track(id: UUID(), kind: .video, clips: [lone, after])
        track.slide(lone.id, by: seconds(-10), sourceDuration: sourceDuration)
        #expect(try clip(lone.id, in: track).timelineStart == .zero)
        track.slide(lone.id, by: seconds(10), sourceDuration: sourceDuration)
        #expect(try clip(lone.id, in: track).timelineRange.end == seconds(6))
        #expect(try clip(after.id, in: track).timelineStart == seconds(6))
    }
}

struct TrimTests {
    private let assetID = UUID()

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    private func clip(at start: Double, sourceStart: Double = 0, length: Double) throws -> Clip {
        try #require(Clip(assetID: assetID, sourceRange: CMTimeRange(start: seconds(sourceStart), duration: seconds(length)), timelineStart: seconds(start)))
    }

    @Test("뒤 끝을 줄이면 뒤 클립이 당겨지고, 늘리면 밀리며, 원본 길이를 넘지 않는다")
    func trimEndRipples() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 4), clip(at: 4, length: 2)])
        let first = track.clips[0]

        track.setSourceRange(first.trimmedSourceRange(edge: .end, by: seconds(-1), sourceDuration: seconds(10)), forClip: first.id)
        #expect(track.clips.map { [$0.timelineStart.seconds, $0.timelineRange.end.seconds] } == [[0, 3], [3, 5]])

        let longer = track.clips[0].trimmedSourceRange(edge: .end, by: seconds(20), sourceDuration: seconds(10))
        #expect(longer.end == seconds(10))
    }

    @Test("앞 끝을 자르면 원본 시작이 늦어지고 클립 시작 위치는 그대로이며 뒤 클립이 당겨진다")
    func trimStartRipples() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 4), clip(at: 4, length: 2)])
        let first = track.clips[0]

        track.setSourceRange(first.trimmedSourceRange(edge: .start, by: seconds(1.5), sourceDuration: seconds(10)), forClip: first.id)

        #expect(track.clips[0].sourceRange.start == seconds(1.5))
        #expect(track.clips[0].timelineStart == .zero)
        #expect(track.clips[1].timelineStart == seconds(2.5))
    }

    @Test("한 프레임보다 짧게 자르지 않고, 앞 끝은 원본 처음보다 앞으로 가지 않는다")
    func trimClamps() throws {
        let original = try clip(at: 0, sourceStart: 1, length: 2)
        #expect(original.trimmedSourceRange(edge: .end, by: seconds(-5), sourceDuration: seconds(10)).duration == Clip.minimumDuration)
        #expect(original.trimmedSourceRange(edge: .start, by: seconds(-5), sourceDuration: seconds(10)).start == .zero)
    }

    @Test("이미지 클립은 원본 길이 제한 없이 늘리고 원본 시작은 0이다")
    func imageTrimHasNoLimit() throws {
        let image = try clip(at: 0, length: 5)
        let longer = image.trimmedSourceRange(edge: .end, by: seconds(30), sourceDuration: nil)
        let shorter = image.trimmedSourceRange(edge: .start, by: seconds(2), sourceDuration: nil)
        #expect(longer.duration == seconds(35))
        #expect(shorter.start == .zero && shorter.duration == seconds(3))
    }
}

struct AudioVolumeTests {
    @Test("들리는 음량은 클립 음량 × 트랙 음량이고, 어느 쪽이든 음소거면 0이다")
    func effectiveVolume() throws {
        var clip = try #require(Clip(assetID: UUID(), sourceRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), timelineStart: .zero))
        clip.volume = 0.5
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [Track(id: UUID(), kind: .audio, clips: [clip])])
        sequence.tracks[0].volume = 0.5
        #expect(sequence.effectiveVolume(of: clip.id) == 0.25)
        sequence.tracks[0].isMuted = true
        #expect(sequence.effectiveVolume(of: clip.id) == 0)
    }
}
