import CoreMedia
import Foundation
@testable import palladium
import Testing

struct TrackTests {
    @Test("클립이 없는 트랙에는 겹침이 없다")
    func emptyTrackHasNoOverlap() {
        let track = Track(id: UUID(), kind: .video, clips: [])
        #expect(!track.hasOverlappingClips)
    }

    @Test("앞 클립이 끝나는 순간 다음 클립이 시작하면 겹침이 아니다")
    func touchingClipsDoNotOverlap() throws {
        let track = try Track(id: UUID(), kind: .video, clips: [
            makeClip(timelineStart: 0, duration: 5),
            makeClip(timelineStart: 5, duration: 5),
        ])
        #expect(!track.hasOverlappingClips)
    }

    @Test("앞 클립이 끝나기 전에 다음 클립이 시작하면 겹침이다")
    func overlappingClipsAreDetected() throws {
        let track = try Track(id: UUID(), kind: .video, clips: [
            makeClip(timelineStart: 0, duration: 5),
            makeClip(timelineStart: 4, duration: 5),
        ])
        #expect(track.hasOverlappingClips)
    }

    @Test("클립 배열 순서와 상관없이 겹침을 찾는다")
    func detectsOverlapRegardlessOfArrayOrder() throws {
        let track = try Track(id: UUID(), kind: .video, clips: [
            makeClip(timelineStart: 10, duration: 5),
            makeClip(timelineStart: 0, duration: 12),
        ])
        #expect(track.hasOverlappingClips)
    }
}

// MARK: - Helpers

private func makeClip(timelineStart: Double, duration: Double) throws -> Clip {
    let sourceRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: standardTimescale))
    return try #require(Clip(assetID: UUID(), sourceRange: sourceRange, timelineStart: CMTime(seconds: timelineStart, preferredTimescale: standardTimescale)))
}
