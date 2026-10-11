import CoreMedia
import Foundation

// 타임라인 병합(#100): 같은 트랙에서 빈틈없이 맞닿은 클립들을 그룹으로 묶어 한 번에 고르고 옮기고 지운다.
// 클립 하나처럼 동작하는 컴파운드 클립이 아니라 묶음이다 — 안의 클립은 각자의 구간·이펙트를 그대로 갖고 합성은 바뀌지 않는다.
// 그룹 안 클립을 따로 트림해도 리플로 안은 붙은 채 유지되고, 다른 클립은 그룹 사이에 끼워 넣지 않는다(그룹 앞이나 뒤로 놓인다).

// MARK: - Track

nonisolated extension Track {
    /// 같은 그룹의 클립들(시각 순).
    func members(ofGroup groupID: UUID) -> [Clip] {
        clips.filter { $0.groupID == groupID }.sorted { $0.timelineStart < $1.timelineStart }
    }

    /// 클립이 차지하는 덩어리 구간: 그룹에 속하면 그 그룹 전체, 아니면 그 클립 구간.
    func blockRange(of clip: Clip) -> CMTimeRange {
        guard let groupID = clip.groupID else { return clip.timelineRange }
        let members = members(ofGroup: groupID)
        guard let first = members.first, let last = members.last else { return clip.timelineRange }
        return CMTimeRange(start: first.timelineStart, end: last.timelineRange.end)
    }

    /// 클립 여러 개를 덩어리 하나로 경계(또는 틈)에 넣고, 뒤 클립과 겹치는 만큼 뒤 클립들을 민다. 서로의 간격은 그대로 둔다.
    mutating func insertBlock(_ block: [Clip], at time: CMTime) {
        guard let blockStart = block.map(\.timelineStart).min(), let blockEnd = block.map(\.timelineRange.end).max() else { return }
        let point = insertionPoint(for: time)
        let duration = blockEnd - blockStart
        let nextStart = clips.filter { $0.timelineStart >= point }.map(\.timelineStart).min()
        let shift = nextStart.map { CMTimeMaximum(.zero, point + duration - $0) } ?? .zero
        for index in clips.indices where clips[index].timelineStart >= point {
            clips[index].timelineStart = clips[index].timelineStart + shift
        }
        for var clip in block {
            clip.timelineStart = point + (clip.timelineStart - blockStart)
            clips.append(clip)
        }
        clips.sort { $0.timelineStart < $1.timelineStart }
    }
}

// MARK: - EditSequence

nonisolated extension EditSequence {
    /// 고른 클립에 그 클립이 속한 그룹의 나머지 클립까지 더한 것. 그룹은 늘 통째로 고르고 옮기고 지운다.
    func expandedToGroups(_ clipIDs: Set<Clip.ID>) -> Set<Clip.ID> {
        let groupIDs = Set(tracks.flatMap(\.clips).filter { clipIDs.contains($0.id) }.compactMap(\.groupID))
        guard !groupIDs.isEmpty else { return clipIDs }
        return clipIDs.union(tracks.flatMap(\.clips).filter { $0.groupID.map(groupIDs.contains) == true }.map(\.id))
    }

    /// 병합할 수 있는지: 그룹까지 넓힌 클립이 2개 이상이고, 한 트랙에서 빈틈없이 맞닿아 있으며, 이미 하나의 그룹이 아니다.
    func canGroup(_ clipIDs: Set<Clip.ID>) -> Bool {
        groupableClips(clipIDs) != nil
    }

    /// 병합 해제할 수 있는지: 고른 클립 중 그룹에 속한 것이 있다.
    func canUngroup(_ clipIDs: Set<Clip.ID>) -> Bool {
        tracks.flatMap(\.clips).contains { clipIDs.contains($0.id) && $0.groupID != nil }
    }

    /// 맞닿은 클립들을 새 그룹으로 묶는다(이미 일부가 그룹이면 그 그룹까지 하나로 합친다). 새 그룹 ID, 묶을 수 없으면 `nil`.
    @discardableResult
    mutating func group(_ clipIDs: Set<Clip.ID>) -> UUID? {
        guard let (trackIndex, members) = groupableClips(clipIDs) else { return nil }
        let groupID = UUID()
        let memberIDs = Set(members.map(\.id))
        for index in tracks[trackIndex].clips.indices where memberIDs.contains(tracks[trackIndex].clips[index].id) {
            tracks[trackIndex].clips[index].groupID = groupID
        }
        return groupID
    }

    /// 고른 클립이 속한 그룹을 모두 푼다. 클립은 그대로 남는다.
    mutating func ungroup(_ clipIDs: Set<Clip.ID>) {
        let groupIDs = Set(tracks.flatMap(\.clips).filter { clipIDs.contains($0.id) }.compactMap(\.groupID))
        updateClips(Set(tracks.flatMap(\.clips).filter { $0.groupID.map(groupIDs.contains) == true }.map(\.id))) { $0.groupID = nil }
    }

    /// 묶을 클립(그룹까지 넓힘, 시각 순)과 그 트랙. 조건을 어기면 `nil`.
    private func groupableClips(_ clipIDs: Set<Clip.ID>) -> (trackIndex: Int, members: [Clip])? {
        let expanded = expandedToGroups(clipIDs)
        guard expanded.count >= 2,
              let trackIndex = tracks.firstIndex(where: { $0.clips.contains { expanded.contains($0.id) } }),
              tracks.indices.allSatisfy({ $0 == trackIndex || !tracks[$0].clips.contains { expanded.contains($0.id) } })
        else { return nil }
        let members = tracks[trackIndex].clips.filter { expanded.contains($0.id) }.sorted { $0.timelineStart < $1.timelineStart }
        let isContiguous = zip(members, members.dropFirst()).allSatisfy { $0.timelineRange.end == $1.timelineStart }
        let groupIDs = Set(members.map(\.groupID))
        let isAlreadyOneGroup = groupIDs.count == 1 && groupIDs.first! != nil
        guard isContiguous, !isAlreadyOneGroup else { return nil }
        return (trackIndex, members)
    }

    /// 그룹을 통째로 다른 시각·트랙으로 옮긴다(#100). `clipID`는 끈 클립, `time`은 그 클립이 놓일 시각이다.
    /// 원래 자리를 메우고(리플) 새 자리 경계에 덩어리로 넣어 뒤 클립을 민다. 같은 트랙에서는 순서 바꾸기가 된다.
    mutating func moveGroup(of clipID: Clip.ID, toTrack trackID: Track.ID, at time: CMTime) {
        guard let sourceIndex = tracks.firstIndex(where: { $0.clips.contains { $0.id == clipID } }),
              let clip = tracks[sourceIndex].clips.first(where: { $0.id == clipID }),
              let groupID = clip.groupID,
              tracks.contains(where: { $0.id == trackID && $0.kind == tracks[sourceIndex].kind })
        else { return }
        let block = tracks[sourceIndex].members(ofGroup: groupID)
        guard let blockStart = block.first?.timelineStart, let blockEnd = block.last?.timelineRange.end else { return }
        let duration = blockEnd - blockStart
        let sourceTrackID = tracks[sourceIndex].id
        removeClips(Set(block.map(\.id)), ripple: true)
        var destination = CMTimeMaximum(time - (clip.timelineStart - blockStart), .zero)
        // 같은 트랙에서 뒤로 옮기면 틈을 메우며 당겨진 만큼 놓을 시각도 앞으로 온다.
        if trackID == sourceTrackID, destination >= blockEnd {
            destination = destination - duration
        } else if trackID == sourceTrackID, destination > blockStart {
            destination = blockStart
        }
        guard let targetIndex = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[targetIndex].insertBlock(block, at: destination)
    }
}
