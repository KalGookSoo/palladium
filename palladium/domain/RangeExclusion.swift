import CoreMedia
import Foundation

/// 클립 편집 창에서 뺀 구간을 다루는 규칙(#99). 바깥 구간(`bounds`)에서 뺀 구간들을 빼고 남은 구간들을 순서대로 이어 붙인다.
/// 뺀 구간은 바깥 구간 안으로 자르고, 겹치거나 맞닿은 구간은 하나로 합친다. 최소 길이(한 프레임)보다 짧게 남는 조각은 버린다.
nonisolated enum RangeExclusion {
    /// 바깥 구간 안으로 자르고 시작 순으로 정렬해 겹치거나 맞닿은 구간을 합친다. 길이가 없는 구간은 버린다.
    static func normalized(_ ranges: [CMTimeRange], within bounds: CMTimeRange) -> [CMTimeRange] {
        let clipped = ranges
            .map { $0.intersection(bounds) }
            .filter { $0.duration > .zero }
            .sorted { $0.start < $1.start }
        var merged: [CMTimeRange] = []
        for range in clipped {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = CMTimeRange(start: last.start, end: CMTimeMaximum(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// 바깥 구간에서 뺀 구간들을 빼고 남은 구간들(시작 순). 최소 길이보다 짧은 조각은 버린다.
    static func kept(bounds: CMTimeRange, excluded: [CMTimeRange]) -> [CMTimeRange] {
        var kept: [CMTimeRange] = []
        var cursor = bounds.start
        for range in normalized(excluded, within: bounds) {
            kept.append(CMTimeRange(start: cursor, end: range.start))
            cursor = range.end
        }
        kept.append(CMTimeRange(start: cursor, end: bounds.end))
        return kept.filter { $0.duration >= Clip.minimumDuration }
    }

    /// 남은 구간들의 길이 합.
    static func keptDuration(bounds: CMTimeRange, excluded: [CMTimeRange]) -> CMTime {
        kept(bounds: bounds, excluded: excluded).reduce(.zero) { $0 + $1.duration }
    }

    /// 남은 구간들을 감싸는 구간과 그 안의 빈 곳(뺀 구간). 저장할 때 이 모양으로 정리한다(양 끝을 뺐으면 바깥 구간이 줄어든다).
    /// 남은 구간이 없으면 `nil`.
    static func hullAndGaps(of kept: [CMTimeRange]) -> (hull: CMTimeRange, gaps: [CMTimeRange])? {
        guard let first = kept.first, let last = kept.last else { return nil }
        let gaps = zip(kept, kept.dropFirst()).map { CMTimeRange(start: $0.end, end: $1.start) }.filter { $0.duration > .zero }
        return (CMTimeRange(start: first.start, end: last.end), gaps)
    }

    /// `time`이 들어 있는 뺀 구간(되살리기 대상). 없으면 `nil`.
    static func excludedRange(containing time: CMTime, in excluded: [CMTimeRange]) -> CMTimeRange? {
        excluded.first { $0.start <= time && time < $0.end }
    }
}
