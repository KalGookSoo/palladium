import CoreMedia
import Foundation

// 롤·슬립·슬라이드 트림(#58). 모두 같은 트랙 안에서만 바꾸고, 시퀀스 전체 길이는 바꾸지 않는다.
// 원본 길이는 `sourceDuration(assetID)`로 받고, `nil`이면(이미지) 길이 제한 없이 늘릴 수 있고 원본 시작은 항상 0이다.

nonisolated extension Clip {
    /// 뒤 끝을 옮길 수 있는 범위(타임라인 기준). 최소 길이는 남기고 원본 끝을 넘지 않는다.
    func endAdjustmentRange(sourceDuration: CMTime?) -> ClosedRange<CMTime> {
        let lower = Self.minimumDuration - sourceRange.duration
        let upper = sourceDuration.map { CMTimeMaximum($0 - sourceRange.end, .zero) } ?? .positiveInfinity
        return CMTimeMinimum(lower, .zero) ... CMTimeMaximum(upper, .zero)
    }

    /// 앞 끝을 옮길 수 있는 범위(오른쪽이 +). 원본 시작 앞으로 가지 않고 최소 길이는 남긴다.
    func startAdjustmentRange(sourceDuration: CMTime?) -> ClosedRange<CMTime> {
        let lower = sourceDuration == nil ? CMTime.negativeInfinity : CMTime.zero - sourceRange.start
        let upper = sourceRange.duration - Self.minimumDuration
        return CMTimeMinimum(lower, .zero) ... CMTimeMaximum(upper, .zero)
    }

    /// 뒤 끝을 옮긴다. 타임라인 시작은 그대로다.
    mutating func moveEnd(by delta: CMTime) {
        sourceRange = CMTimeRange(start: sourceRange.start, duration: sourceRange.duration + delta)
    }

    /// 앞 끝을 옮긴다. 이미지(`isStill`)는 원본 시작을 0으로 두고 길이만 바꾼다.
    mutating func moveStart(by delta: CMTime, isStill: Bool) {
        timelineStart = timelineStart + delta
        let start = isStill ? CMTime.zero : sourceRange.start + delta
        sourceRange = CMTimeRange(start: start, duration: sourceRange.duration - delta)
    }
}

nonisolated extension Track {
    /// 끝이 `clip`의 시작과 맞닿은 앞 클립 위치.
    private func adjacentIndex(before clip: Clip) -> Int? {
        clips.firstIndex { $0.id != clip.id && $0.timelineRange.end == clip.timelineStart }
    }

    /// 시작이 `clip`의 끝과 맞닿은 뒤 클립 위치.
    private func adjacentIndex(after clip: Clip) -> Int? {
        clips.firstIndex { $0.id != clip.id && $0.timelineStart == clip.timelineRange.end }
    }

    /// 롤: 맞닿은 두 클립의 경계를 `delta`만큼 옮긴다. 한쪽이 길어진 만큼 다른 쪽이 짧아져 전체 길이는 그대로다.
    /// `edge`가 `.end`면 이 클립과 뒤 클립 사이, `.start`면 앞 클립과 이 클립 사이 경계다. 맞닿은 클립이 없으면 바꾸지 않는다.
    /// 반환값은 실제로 옮긴 양이다.
    @discardableResult
    mutating func roll(_ clipID: Clip.ID, edge: ClipEdge, by delta: CMTime, sourceDuration: (MediaAsset.ID) -> CMTime?) -> CMTime {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return .zero }
        let pair: (left: Int, right: Int)?
        switch edge {
        case .end: pair = adjacentIndex(after: clips[index]).map { (index, $0) }
        case .start: pair = adjacentIndex(before: clips[index]).map { ($0, index) }
        }
        guard let (left, right) = pair else { return .zero }
        let leftRange = clips[left].endAdjustmentRange(sourceDuration: sourceDuration(clips[left].assetID))
        let rightSource = sourceDuration(clips[right].assetID)
        let rightRange = clips[right].startAdjustmentRange(sourceDuration: rightSource)
        let applied = Self.clamp(delta, lower: CMTimeMaximum(leftRange.lowerBound, rightRange.lowerBound), upper: CMTimeMinimum(leftRange.upperBound, rightRange.upperBound))
        clips[left].moveEnd(by: applied)
        clips[right].moveStart(by: applied, isStill: rightSource == nil)
        return applied
    }

    /// 슬립: 클립 위치·길이는 두고 원본에서 쓰는 구간만 `delta`만큼 옮긴다. 원본 범위를 넘지 않는다. 이미지는 바꾸지 않는다.
    @discardableResult
    mutating func slip(_ clipID: Clip.ID, by delta: CMTime, sourceDuration: CMTime?) -> CMTime {
        guard let index = clips.firstIndex(where: { $0.id == clipID }), let sourceDuration else { return .zero }
        let range = clips[index].sourceRange
        let applied = Self.clamp(delta, lower: CMTime.zero - range.start, upper: CMTimeMaximum(sourceDuration - range.end, .zero))
        clips[index].sourceRange = CMTimeRange(start: range.start + applied, duration: range.duration)
        return applied
    }

    /// 슬라이드: 클립 길이·원본 구간은 두고 위치를 `delta`만큼 옮긴다. 맞닿은 앞 클립은 끝이, 맞닿은 뒤 클립은 시작이 따라 바뀌고,
    /// 맞닿지 않은 쪽은 틈 안에서만 움직인다. 전체 길이는 그대로다.
    @discardableResult
    mutating func slide(_ clipID: Clip.ID, by delta: CMTime, sourceDuration: (MediaAsset.ID) -> CMTime?) -> CMTime {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return .zero }
        let clip = clips[index]
        let previous = adjacentIndex(before: clip)
        let next = adjacentIndex(after: clip)
        var lower = CMTime.negativeInfinity
        var upper = CMTime.positiveInfinity
        if let previous {
            let range = clips[previous].endAdjustmentRange(sourceDuration: sourceDuration(clips[previous].assetID))
            lower = CMTimeMaximum(lower, range.lowerBound)
            upper = CMTimeMinimum(upper, range.upperBound)
        } else {
            let gapStart = clips.filter { $0.timelineRange.end <= clip.timelineStart }.map(\.timelineRange.end).max() ?? .zero
            lower = CMTimeMaximum(lower, gapStart - clip.timelineStart)
        }
        if let next {
            let range = clips[next].startAdjustmentRange(sourceDuration: sourceDuration(clips[next].assetID))
            lower = CMTimeMaximum(lower, range.lowerBound)
            upper = CMTimeMinimum(upper, range.upperBound)
        } else if let gapEnd = clips.filter({ $0.timelineStart >= clip.timelineRange.end }).map(\.timelineStart).min() {
            upper = CMTimeMinimum(upper, gapEnd - clip.timelineRange.end)
        }
        let applied = Self.clamp(delta, lower: lower, upper: upper)
        if let previous {
            clips[previous].moveEnd(by: applied)
        }
        clips[index].timelineStart = clip.timelineStart + applied
        if let next {
            clips[next].moveStart(by: applied, isStill: sourceDuration(clips[next].assetID) == nil)
        }
        return applied
    }

    private static func clamp(_ delta: CMTime, lower: CMTime, upper: CMTime) -> CMTime {
        guard lower <= upper else { return .zero }
        return CMTimeMinimum(CMTimeMaximum(delta, lower), upper)
    }
}

nonisolated extension EditSequence {
    mutating func roll(_ clipID: Clip.ID, edge: ClipEdge, by delta: CMTime, sourceDuration: (MediaAsset.ID) -> CMTime?) {
        updateTrack(containing: clipID) { $0.roll(clipID, edge: edge, by: delta, sourceDuration: sourceDuration) }
    }

    mutating func slip(_ clipID: Clip.ID, by delta: CMTime, sourceDuration: (MediaAsset.ID) -> CMTime?) {
        updateTrack(containing: clipID) { track in
            guard let assetID = track.clips.first(where: { $0.id == clipID })?.assetID else { return }
            track.slip(clipID, by: delta, sourceDuration: sourceDuration(assetID))
        }
    }

    mutating func slide(_ clipID: Clip.ID, by delta: CMTime, sourceDuration: (MediaAsset.ID) -> CMTime?) {
        updateTrack(containing: clipID) { $0.slide(clipID, by: delta, sourceDuration: sourceDuration) }
    }

    private mutating func updateTrack(containing clipID: Clip.ID, _ change: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipID } }) else { return }
        change(&tracks[index])
    }
}
