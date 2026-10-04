import CoreMedia
import Foundation
@testable import palladium
import Testing

struct TimelineEditingTests {
    private let assetID = UUID()

    @Test("덮어쓰기는 놓는 구간의 기존 클립을 잘라내고, 구간을 감싸는 클립은 둘로 나눈다")
    func overwriteTrimsAndSplits() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 10)])

        try track.place(clip(at: 4, length: 2), mode: .overwrite)

        #expect(spans(of: track) == [[0, 4], [4, 6], [6, 10]])
        // 뒷부분은 원본에서도 6초부터 이어진다.
        #expect(track.clips[2].sourceRange.start.seconds == 6)
        #expect(!track.hasOverlappingClips)
    }

    @Test("덮어쓰기는 구간 안에 완전히 들어간 클립을 지우고 걸친 클립의 앞뒤를 자른다")
    func overwriteRemovesCoveredClips() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [
            clip(at: 0, length: 3), clip(at: 3, length: 2), clip(at: 5, length: 5),
        ])

        try track.place(clip(at: 2, length: 5), mode: .overwrite)

        #expect(spans(of: track) == [[0, 2], [2, 7], [7, 10]])
    }

    @Test("삽입은 놓는 지점 뒤 클립을 밀고, 지점에 걸친 클립은 나눠 뒷부분만 민다")
    func insertShiftsAndSplits() throws {
        var track = try Track(id: UUID(), kind: .video, clips: [clip(at: 0, length: 4), clip(at: 4, length: 4)])

        try track.place(clip(at: 2, length: 3), mode: .insert)

        #expect(spans(of: track) == [[0, 2], [2, 5], [5, 7], [7, 11]])
        #expect(track.clips[2].sourceRange.start.seconds == 2)
    }

    @Test("새 영상 트랙은 기존 영상 트랙 앞에, 새 오디오 트랙은 맨 뒤에 추가된다")
    func addTrackOrder() {
        var sequence = SampleData.mainSequence
        let videoID = sequence.addTrack(kind: .video)
        let audioID = sequence.addTrack(kind: .audio)

        #expect(sequence.tracks.first?.id == videoID)
        #expect(sequence.tracks.last?.id == audioID)
    }

    @Test("가까운 클립 경계나 0초에 붙이고, 허용 범위 밖이면 그대로 둔다")
    func snapping() throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(clip(at: 2, length: 3), onTrack: trackID, mode: .overwrite)
        let tolerance = seconds(0.3)

        #expect(sequence.snappedTime(seconds(4.8), tolerance: tolerance) == seconds(5))
        #expect(sequence.snappedTime(seconds(0.2), tolerance: tolerance) == .zero)
        #expect(sequence.snappedTime(seconds(3.5), tolerance: tolerance) == seconds(3.5))
    }

    @Test("이미지는 영상 트랙에 정해진 길이로, 오디오는 오디오 트랙에 원본 길이로 놓인다")
    func placementDefaults() {
        let image = MediaAsset(id: UUID(), name: "logo.png", sourceURL: URL(filePath: "/logo.png"), kind: .image, duration: .zero)
        #expect(image.trackKind == .video)
        #expect(image.placementDuration == MediaAsset.stillImageDuration)
        #expect(SampleData.backgroundMusic.trackKind == .audio)
        #expect(SampleData.backgroundMusic.placementDuration == SampleData.backgroundMusic.duration)
    }

    // MARK: - Helpers

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
