import CoreMedia
@testable import palladium
import Testing

struct PlaybackTimelineTests {
    private let videoTimeline = PlaybackTimeline(duration: seconds(10), frameDuration: CMTime(value: 1, timescale: 30))
    private let audioTimeline = PlaybackTimeline(duration: seconds(10), frameDuration: nil)

    @Test("한 프레임 앞으로 가면 프레임 길이만큼 이동한다")
    func stepsForwardByOneFrame() {
        #expect(videoTimeline.steppedTime(from: seconds(1), byFrames: 1) == seconds(1) + CMTime(value: 1, timescale: 30))
    }

    @Test("처음에서 한 프레임 뒤로 가면 0초에 머문다")
    func stepBackwardStopsAtStart() {
        #expect(videoTimeline.steppedTime(from: .zero, byFrames: -1) == .zero)
    }

    @Test("끝에서 한 프레임 앞으로 가면 끝에 머문다")
    func stepForwardStopsAtEnd() {
        #expect(videoTimeline.steppedTime(from: seconds(10), byFrames: 1) == seconds(10))
    }

    @Test("영상 트랙이 없으면 프레임 이동을 할 수 없고 위치도 그대로다")
    func audioCannotStepFrames() {
        #expect(!audioTimeline.canStepFrames)
        #expect(audioTimeline.steppedTime(from: seconds(3), byFrames: 1) == seconds(3))
    }

    @Test("스크럽 위치와 재생 시각은 서로 변환된다")
    func progressAndTimeRoundTrip() {
        #expect(videoTimeline.progress(at: seconds(2.5)) == 0.25)
        #expect(videoTimeline.time(atProgress: 0.25) == seconds(2.5))
    }

    @Test("범위를 벗어난 스크럽 위치는 처음과 끝으로 제한된다")
    func progressOutOfRangeIsClamped() {
        #expect(videoTimeline.time(atProgress: -0.5) == .zero)
        #expect(videoTimeline.time(atProgress: 1.5) == seconds(10))
    }

    @Test("전체 길이가 0이면 스크럽 위치는 0이다")
    func zeroDurationProgressIsZero() {
        let emptyTimeline = PlaybackTimeline(duration: .zero, frameDuration: nil)
        #expect(emptyTimeline.progress(at: seconds(1)) == 0)
    }

    @Test("시간 표시는 현재 위치와 전체 길이를 분:초로 보여준다")
    func timeLabelShowsCurrentAndTotal() {
        let timeline = PlaybackTimeline(duration: seconds(48), frameDuration: nil)
        #expect(timeline.timeLabel(at: seconds(12)) == "00:12 / 00:48")
    }
}

// MARK: - Helpers

private func seconds(_ value: Double) -> CMTime {
    CMTime(seconds: value, preferredTimescale: standardTimescale)
}
