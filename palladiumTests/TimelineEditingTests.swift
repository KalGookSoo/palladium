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
