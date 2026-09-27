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
}

// MARK: - Helpers

private func seconds(_ value: Double) -> CMTime {
    CMTime(seconds: value, preferredTimescale: 600)
}

private func range(start: Double, duration: Double) -> CMTimeRange {
    CMTimeRange(start: seconds(start), duration: seconds(duration))
}
