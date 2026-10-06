import CoreMedia
import Foundation
@testable import palladium
import Testing

struct ClipTests {
    @Test("유효한 구간과 0 이상의 시작 위치로는 클립을 만들 수 있다")
    func createsClipWithValidValues() {
        let clip = Clip(assetID: UUID(), sourceRange: range(start: 0, duration: 5), timelineStart: seconds(0))
        #expect(clip != nil)
    }

    @Test("길이가 0인 구간으로는 클립을 만들 수 없다")
    func rejectsZeroDurationRange() {
        let clip = Clip(assetID: UUID(), sourceRange: range(start: 0, duration: 0), timelineStart: seconds(0))
        #expect(clip == nil)
    }

    @Test("유효하지 않은 구간으로는 클립을 만들 수 없다")
    func rejectsInvalidRange() {
        let clip = Clip(assetID: UUID(), sourceRange: .invalid, timelineStart: seconds(0))
        #expect(clip == nil)
    }

    @Test("길이가 무한한 구간으로는 클립을 만들 수 없다")
    func rejectsInfiniteDuration() {
        let infiniteRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        let clip = Clip(assetID: UUID(), sourceRange: infiniteRange, timelineStart: seconds(0))
        #expect(clip == nil)
    }

    @Test("타임라인 시작 위치가 음수이면 클립을 만들 수 없다")
    func rejectsNegativeTimelineStart() {
        let clip = Clip(assetID: UUID(), sourceRange: range(start: 0, duration: 5), timelineStart: seconds(-1))
        #expect(clip == nil)
    }

    @Test("타임라인 구간은 시작 위치에서 원본 구간 길이만큼 이어진다")
    func timelineRangeUsesSourceDuration() throws {
        let clip = try #require(Clip(assetID: UUID(), sourceRange: range(start: 3, duration: 5), timelineStart: seconds(10)))
        #expect(clip.timelineRange == range(start: 10, duration: 5))
    }

    @Test("트림을 끄는 동안 보이는 클립은 잡은 끝만 움직이고 반대쪽 끝은 그대로다(속도를 바꾼 클립도)")
    func trimDisplayKeepsOppositeEdge() throws {
        let clip = try #require(Clip(assetID: UUID(), sourceRange: range(start: 2, duration: 10), timelineStart: seconds(10)))

        let startCut = clip.trimDisplay(edge: .start, sourceRange: range(start: 4, duration: 8))
        #expect(startCut.timelineRange == range(start: 12, duration: 8))
        let startExtended = clip.trimDisplay(edge: .start, sourceRange: range(start: 0, duration: 12))
        #expect(startExtended.timelineRange == range(start: 8, duration: 12))
        let endCut = clip.trimDisplay(edge: .end, sourceRange: range(start: 2, duration: 7))
        #expect(endCut.timelineRange == range(start: 10, duration: 7))
        #expect(endCut.id == clip.id && endCut.sourceRange == range(start: 2, duration: 7))

        var fast = clip
        fast.speed = 2
        // 원본 10초 → 타임라인 5초(10~15초). 앞을 2초(원본) 자르면 타임라인 1초가 줄어 11~15초.
        #expect(fast.trimDisplay(edge: .start, sourceRange: range(start: 4, duration: 8)).timelineRange == range(start: 11, duration: 4))
    }
}

// MARK: - Helpers

private func seconds(_ value: Double) -> CMTime {
    CMTime(seconds: value, preferredTimescale: standardTimescale)
}

private func range(start: Double, duration: Double) -> CMTimeRange {
    CMTimeRange(start: seconds(start), duration: seconds(duration))
}
