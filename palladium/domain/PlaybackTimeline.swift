import CoreMedia
import Foundation

/// 재생 중인 미디어 하나의 시간 축. 재생 위치 계산을 AVPlayer 밖에서 검증할 수 있게 순수 값으로 둔다.
nonisolated struct PlaybackTimeline {
    let duration: CMTime
    /// 영상 트랙이 없으면 `nil`이며, 이때는 프레임 단위로 이동할 수 없다.
    let frameDuration: CMTime?
}

// MARK: - Queries

nonisolated extension PlaybackTimeline {
    var canStepFrames: Bool {
        frameDuration != nil
    }

    func clamped(_ time: CMTime) -> CMTime {
        CMTimeClampToRange(time, range: CMTimeRange(start: .zero, duration: duration))
    }

    func steppedTime(from time: CMTime, byFrames frameCount: Int) -> CMTime {
        guard let frameDuration else { return clamped(time) }
        let offset = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
        return clamped(time + offset)
    }

    /// 전체 길이가 0이면 0을 돌려준다.
    func progress(at time: CMTime) -> Double {
        guard duration.seconds > 0 else { return 0 }
        return clamped(time).seconds / duration.seconds
    }

    func time(atProgress progress: Double) -> CMTime {
        let clampedProgress = min(max(progress, 0), 1)
        return clamped(CMTimeMultiplyByFloat64(duration, multiplier: clampedProgress))
    }

    func timeLabel(at time: CMTime) -> String {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2))
        let current = Duration.seconds(clamped(time).seconds).formatted(format)
        let total = Duration.seconds(duration.seconds).formatted(format)
        return "\(current) / \(total)"
    }
}
