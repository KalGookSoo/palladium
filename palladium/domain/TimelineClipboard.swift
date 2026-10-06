import CoreMedia
import Foundation

/// 앱 안에서만 쓰는 타임라인 클립보드(#62). 지금 선택 구조대로 클립 여러 개, 자막 하나, 마스크 하나 중 하나를 담는다.
nonisolated enum TimelineClipboard: Equatable {
    case clips([CopiedClip])
    case subtitle(Subtitle)
    case mask(Mask)
}

/// 복사한 클립과 원래 트랙. `clip.timelineStart`는 복사한 묶음의 시작(가장 먼저 시작하는 클립)부터의 거리다.
nonisolated struct CopiedClip: Equatable {
    var clip: Clip
    let trackID: Track.ID
    let trackKind: TrackKind
    /// 화면에 보이는 트랙 번호(영상은 맨 아래가 1, 오디오는 맨 위가 1). 다른 시퀀스에서 같은 번호의 트랙을 찾는 데 쓴다.
    let trackNumber: Int
}

/// 붙여넣은 것. 화면이 붙여넣은 것을 고르는 데 쓴다.
nonisolated enum PastedItems: Equatable {
    case clips(Set<Clip.ID>)
    case subtitle(Subtitle.ID)
    case mask(Mask.ID)
}

nonisolated extension Clip {
    /// 모든 속성이 같고 ID만 새로 받은 클립.
    func duplicated(id: UUID = UUID()) -> Clip? {
        portion(from: timelineStart, to: timelineRange.end, id: id)
    }
}

nonisolated extension EditSequence {
    /// 화면에 보이는 트랙 번호. 영상은 프리미어처럼 맨 아래(메인)가 1이고, 오디오는 위에서부터 1이다.
    func trackNumber(at index: Int) -> Int {
        let kind = tracks[index].kind
        return kind == .video
            ? tracks[index...].filter { $0.kind == .video }.count
            : tracks[...index].filter { $0.kind == .audio }.count
    }

    /// 고른 클립을 복사한다. 시각은 묶음의 시작부터의 거리로 바꾼다. 고른 클립이 없으면 빈 배열이다.
    func copiedClips(_ clipIDs: Set<Clip.ID>) -> [CopiedClip] {
        let copied = tracks.indices.flatMap { index in
            tracks[index].clips.filter { clipIDs.contains($0.id) }.map { clip in
                CopiedClip(clip: clip, trackID: tracks[index].id, trackKind: tracks[index].kind, trackNumber: trackNumber(at: index))
            }
        }
        guard let blockStart = copied.map(\.clip.timelineStart).min() else { return [] }
        return copied.map { item in
            var item = item
            item.clip.timelineStart = item.clip.timelineStart - blockStart
            return item
        }
    }

    /// 복사한 클립을 `time`에 붙이고 새 ID 목록을 돌려준다(#62).
    /// 트랙은 원래 트랙이 있으면 그 트랙, 없으면 같은 번호의 같은 종류 트랙(모자라면 가장 가까운 번호)이다.
    /// 그 종류 트랙이 하나도 없으면 그 클립은 붙이지 않는다(새 트랙을 만들지 않는다).
    /// 묶음에서 가장 먼저 시작하는 클립의 트랙(기준 트랙)에서 삽입 규칙대로 경계를 맞추고, 그 시각을 모든 트랙에 같이 써
    /// 트랙 사이 상대 위치를 지킨다. 다른 트랙에서 그 자리에 걸친 클립이 있으면 그 클립 뒤 경계로 옮긴다(나누지 않는다).
    mutating func paste(_ copied: [CopiedClip], at time: CMTime) -> Set<Clip.ID> {
        let placed = copied.compactMap { item in targetTrackIndex(for: item).map { (trackIndex: $0, item: item) } }
        guard let anchor = placed.min(by: { $0.item.clip.timelineStart < $1.item.clip.timelineStart }) else { return [] }
        let blockStart = tracks[anchor.trackIndex].insertionPoint(for: time) - anchor.item.clip.timelineStart

        var pastedIDs: Set<Clip.ID> = []
        for trackIndex in Set(placed.map(\.trackIndex)) {
            let group = placed.filter { $0.trackIndex == trackIndex }.compactMap { entry -> Clip? in
                var clip = entry.item.clip.duplicated()
                clip?.timelineStart = blockStart + entry.item.clip.timelineStart
                return clip
            }
            tracks[trackIndex].insert(contentsOf: group)
            pastedIDs.formUnion(group.map(\.id))
        }
        return pastedIDs
    }

    /// 자막을 새 ID로 `time`에 같은 길이·글자·스타일로 붙인다. 다른 자막은 밀지 않는다.
    mutating func paste(_ subtitle: Subtitle, at time: CMTime) -> Subtitle.ID {
        let copy = Subtitle(id: UUID(), range: CMTimeRange(start: CMTimeMaximum(time, .zero), duration: subtitle.range.duration), text: subtitle.text, style: subtitle.style)
        addSubtitles([copy])
        return copy.id
    }

    /// 마스크를 새 ID로 `time`에 같은 길이·영역·모양·효과로 붙인다. 다른 마스크는 밀지 않는다.
    mutating func paste(_ mask: Mask, at time: CMTime) -> Mask.ID {
        let copy = Mask(
            id: UUID(), range: CMTimeRange(start: CMTimeMaximum(time, .zero), duration: mask.range.duration),
            area: mask.area, shape: mask.shape, effect: mask.effect, strength: mask.strength
        )
        masks.append(copy)
        masks.sort { $0.range.start < $1.range.start }
        return copy.id
    }

    private func targetTrackIndex(for item: CopiedClip) -> Int? {
        if let index = tracks.firstIndex(where: { $0.id == item.trackID && $0.kind == item.trackKind }) {
            return index
        }
        return tracks.indices
            .filter { tracks[$0].kind == item.trackKind }
            .min { abs(trackNumber(at: $0) - item.trackNumber) < abs(trackNumber(at: $1) - item.trackNumber) }
    }
}

nonisolated extension Track {
    /// 클립 묶음(사이 틈 포함)을 그 시각 그대로 넣는다. 묶음 시작이 기존 클립 중간이면 그 클립 뒤 경계로 옮기고,
    /// 묶음과 겹치는 만큼 뒤 클립들을 민다. 기존 클립은 나누지 않는다.
    mutating func insert(contentsOf group: [Clip]) {
        guard let groupStart = group.map(\.timelineStart).min() else { return }
        let straddled = clips.first { $0.timelineStart < groupStart && groupStart < $0.timelineRange.end }
        let delta = straddled.map { $0.timelineRange.end - groupStart } ?? .zero
        let moved = group.map { clip in
            var clip = clip
            clip.timelineStart = clip.timelineStart + delta
            return clip
        }
        let point = groupStart + delta
        let groupEnd = moved.map(\.timelineRange.end).max() ?? point
        let nextStart = clips.filter { $0.timelineStart >= point }.map(\.timelineStart).min()
        let shift = nextStart.map { CMTimeMaximum(.zero, groupEnd - $0) } ?? .zero
        for index in clips.indices where clips[index].timelineStart >= point {
            clips[index].timelineStart = clips[index].timelineStart + shift
        }
        clips.append(contentsOf: moved)
        clips.sort { $0.timelineStart < $1.timelineStart }
    }
}
