import CoreMedia
import Foundation

/// 트림 시트(#81)에서 원본 구간을 고르는 규칙. 원본 범위(0~`sourceDuration`) 안에 두고 최소 길이(한 프레임)를 남긴다.
nonisolated enum TrimRange {
    /// ↑/↓ 한 번에 옮기는 시간.
    static let smallStep = CMTime(value: 60, timescale: standardTimescale)
    /// ⇧↑/↓ 한 번에 옮기는 시간.
    static let largeStep = CMTime(value: 600, timescale: standardTimescale)

    /// `start`~`end`를 원본 범위 안으로 맞춘다. 끝을 먼저 맞추고, 시작은 끝보다 최소 길이만큼 앞에 둔다.
    static func clamped(start: CMTime, end: CMTime, sourceDuration: CMTime) -> CMTimeRange {
        let minimum = Clip.minimumDuration
        let clampedEnd = CMTimeMinimum(CMTimeMaximum(end, minimum), sourceDuration)
        let clampedStart = CMTimeMinimum(CMTimeMaximum(start, .zero), clampedEnd - minimum)
        return CMTimeRange(start: clampedStart, end: clampedEnd)
    }

    /// 한쪽 끝만 `delta`만큼 옮긴다. 반대쪽 끝은 그대로 두고, 원본 밖이나 반대쪽 끝을 넘어가지 않는다.
    static func nudging(_ range: CMTimeRange, edge: ClipEdge, by delta: CMTime, sourceDuration: CMTime) -> CMTimeRange {
        moving(range, edge: edge, to: (edge == .start ? range.start : range.end) + delta, sourceDuration: sourceDuration)
    }

    /// 한쪽 끝을 `time`으로 옮긴다(손잡이 끌기). 반대쪽 끝은 그대로 둔다.
    static func moving(_ range: CMTimeRange, edge: ClipEdge, to time: CMTime, sourceDuration: CMTime) -> CMTimeRange {
        let minimum = Clip.minimumDuration
        switch edge {
        case .start:
            let start = CMTimeMinimum(CMTimeMaximum(time, .zero), range.end - minimum)
            return CMTimeRange(start: start, end: range.end)
        case .end:
            let end = CMTimeMaximum(CMTimeMinimum(time, sourceDuration), range.start + minimum)
            return CMTimeRange(start: range.start, end: end)
        }
    }

    /// 재생 위치에서 나눌 수 있는지. 구간 안쪽(양 끝 제외)이어야 한다.
    static func canSplit(_ range: CMTimeRange, at time: CMTime) -> Bool {
        range.start < time && time < range.end
    }
}
