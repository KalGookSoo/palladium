import CoreMedia
import Foundation

// MARK: - EditSequence

nonisolated extension EditSequence {
    /// 편집점으로 볼 만큼 가까운 거리(60fps 반 프레임). 재생 헤드가 편집점에 거의 붙어 있으면 그 편집점을 건너뛴다.
    static let editPointTolerance = CMTime(value: 1, timescale: 120)

    /// 재생 헤드가 멈출 편집점(#64, ↑/↓): 0초와 모든 트랙 클립의 시작·끝. 시각 순이고 겹치지 않는다.
    var editPoints: [CMTime] {
        let times = [CMTime.zero] + tracks.flatMap(\.clips).flatMap { [$0.timelineStart, $0.timelineRange.end] }
        return Set(times.map { CMTimeConvertScale($0, timescale: 60000, method: .roundHalfAwayFromZero) }).sorted()
    }

    /// `time`보다 앞의 가장 가까운 편집점. 없으면 `nil`.
    func previousEditPoint(before time: CMTime) -> CMTime? {
        editPoints.last { $0 < time - Self.editPointTolerance }
    }

    /// `time`보다 뒤의 가장 가까운 편집점. 없으면 `nil`.
    func nextEditPoint(after time: CMTime) -> CMTime? {
        editPoints.first { $0 > time + Self.editPointTolerance }
    }

    /// 기본 전환(#64, ⇧⌘T)을 넣을 클립. 고른 클립이 있으면 그중 앞 클립과 맞닿은 것, 없으면 재생 헤드에서 시작하며
    /// 앞 클립과 맞닿은 클립(모든 트랙)이다. 전환을 둘 만큼 두 클립이 길어야 한다.
    func defaultTransitionTargets(selected: Set<Clip.ID>, playhead: CMTime) -> [Clip.ID] {
        tracks.flatMap { track in
            track.clips.filter { clip in
                let isTarget = selected.isEmpty
                    ? abs((clip.timelineStart - playhead).seconds) <= Self.editPointTolerance.seconds
                    : selected.contains(clip.id)
                return isTarget && track.maximumTransitionDuration(into: clip) >= ClipTransition.minimumDuration
            }
            .map(\.id)
        }
    }
}

// MARK: - TimelineScale

nonisolated extension TimelineScale {
    /// `duration` 전체가 폭 `width`에 들어오는 배율(#64, 타임라인 전체 보기 ⇧Z). 허용 범위로 맞추고, 길이나 폭이 없으면 기본 배율이다.
    static func fitting(_ duration: CMTime, into width: Double) -> TimelineScale {
        guard duration.seconds > 0, width > 0 else { return TimelineScale(pointsPerSecond: 40) }
        return TimelineScale(pointsPerSecond: width / duration.seconds)
    }
}

// MARK: - Shuttle

/// J/K/L 재생 속도(#64, Final Cut·Premiere·QuickTime 공통). L은 앞으로, J는 거꾸로 재생하고 같은 쪽을 다시 누르면 2배·4배로 빨라진다.
/// 반대쪽을 누르면 그쪽 1배로 바뀐다. K는 멈춤이다.
nonisolated enum ShuttleRate {
    static let maximum: Float = 4

    static func next(from rate: Float, forward: Bool) -> Float {
        let direction: Float = forward ? 1 : -1
        guard rate * direction > 0 else { return direction }
        return direction * min(abs(rate) * 2, maximum)
    }
}
