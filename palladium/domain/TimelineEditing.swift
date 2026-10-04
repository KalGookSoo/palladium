import CoreMedia
import Foundation

/// 이미 클립이 있는 자리에 새 클립을 놓는 방식.
nonisolated enum PlacementMode {
    /// 놓는 지점 뒤의 클립을 새 클립 길이만큼 뒤로 민다. 놓는 지점에 걸친 클립은 둘로 나눈다(기본).
    case insert
    /// 놓는 구간의 기존 클립을 잘라내고 덮는다. 오버레이처럼 다른 것과 시간을 맞춰 둔 트랙에 쓴다.
    case overwrite
}

// MARK: - Clip

nonisolated extension Clip {
    /// 타임라인 구간 `[start, end)`에 해당하는 부분만 남긴 클립. 겹치는 부분이 없으면 `nil`.
    /// 앞부분을 잘라내면 원본 구간의 시작도 같은 만큼 뒤로 간다.
    func portion(from start: CMTime, to end: CMTime, id: UUID) -> Clip? {
        let clippedStart = CMTimeMaximum(start, timelineStart)
        let clippedEnd = CMTimeMinimum(end, timelineRange.end)
        guard clippedStart < clippedEnd else { return nil }
        let sourceStart = sourceRange.start + (clippedStart - timelineStart)
        return Clip(
            id: id,
            assetID: assetID,
            sourceRange: CMTimeRange(start: sourceStart, duration: clippedEnd - clippedStart),
            timelineStart: clippedStart
        )
    }
}

// MARK: - Track

nonisolated extension Track {
    mutating func place(_ clip: Clip, mode: PlacementMode) {
        switch mode {
        case .overwrite: overwrite(with: clip)
        case .insert: insert(clip)
        }
    }

    /// 놓는 구간과 겹치는 클립은 겹치지 않는 앞뒤 부분만 남긴다. 구간을 감싸는 클립은 둘로 나뉜다.
    private mutating func overwrite(with clip: Clip) {
        let range = clip.timelineRange
        clips = clips.flatMap { existing -> [Clip] in
            guard existing.timelineRange.end > range.start, existing.timelineStart < range.end else { return [existing] }
            let head = existing.portion(from: existing.timelineStart, to: range.start, id: existing.id)
            let tail = existing.portion(from: range.end, to: existing.timelineRange.end, id: head == nil ? existing.id : UUID())
            return [head, tail].compactMap(\.self)
        }
        clips.append(clip)
        clips.sort { $0.timelineStart < $1.timelineStart }
    }

    /// `ripple`이면 지운 클립 뒤의 클립을 지운 길이만큼 당겨 틈을 메운다.
    mutating func removeClip(id: Clip.ID, ripple: Bool) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let removed = clips.remove(at: index)
        guard ripple else { return }
        for index in clips.indices where clips[index].timelineStart >= removed.timelineRange.end {
            clips[index].timelineStart = clips[index].timelineStart - removed.sourceRange.duration
        }
    }

    /// `time`에 걸친 클립을 둘로 나눈다. 고른 클립(`clipIDs`)이 있으면 그 클립만 나눈다.
    mutating func split(at time: CMTime, clipIDs: Set<Clip.ID>?) {
        clips = clips.flatMap { clip -> [Clip] in
            guard clipIDs?.contains(clip.id) ?? true, clip.timelineStart < time, time < clip.timelineRange.end else { return [clip] }
            return [
                clip.portion(from: clip.timelineStart, to: time, id: clip.id),
                clip.portion(from: time, to: clip.timelineRange.end, id: UUID()),
            ].compactMap(\.self)
        }
    }

    private mutating func insert(_ clip: Clip) {
        let point = clip.timelineStart
        let shift = clip.sourceRange.duration
        clips = clips.flatMap { existing -> [Clip] in
            if existing.timelineStart >= point {
                var moved = existing
                moved.timelineStart = existing.timelineStart + shift
                return [moved]
            }
            guard existing.timelineRange.end > point else { return [existing] }
            // 놓는 지점에 걸친 클립은 지점에서 나눠 뒷부분만 민다.
            let head = existing.portion(from: existing.timelineStart, to: point, id: existing.id)
            var tail = existing.portion(from: point, to: existing.timelineRange.end, id: UUID())
            tail?.timelineStart = point + shift
            return [head, tail].compactMap(\.self)
        }
        clips.append(clip)
        clips.sort { $0.timelineStart < $1.timelineStart }
    }
}

// MARK: - EditSequence

nonisolated extension EditSequence {
    /// 새 영상 트랙은 기존 영상 트랙들 앞(화면 위쪽, 겹칠 때 앞에 그려짐)에, 새 오디오 트랙은 맨 뒤에 둔다.
    @discardableResult
    mutating func addTrack(kind: TrackKind) -> Track.ID {
        let track = Track(id: UUID(), kind: kind, clips: [])
        switch kind {
        case .video:
            tracks.insert(track, at: tracks.firstIndex { $0.kind == .video } ?? 0)
        case .audio:
            tracks.append(track)
        }
        return track.id
    }

    /// 없는 트랙이면 아무것도 하지 않는다.
    mutating func place(_ clip: Clip, onTrack trackID: Track.ID, mode: PlacementMode) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].place(clip, mode: mode)
    }

    func clip(id: Clip.ID) -> Clip? {
        tracks.lazy.flatMap(\.clips).first { $0.id == id }
    }

    func trackID(containing clipID: Clip.ID) -> Track.ID? {
        tracks.first { $0.clips.contains { $0.id == clipID } }?.id
    }

    /// 고른 클립을 지운다. `ripple`이면 각 트랙에서 뒤 클립을 당겨 틈을 메운다(리플 삭제).
    mutating func removeClips(_ clipIDs: Set<Clip.ID>, ripple: Bool) {
        for trackIndex in tracks.indices {
            // 뒤쪽 클립부터 지워야 앞 클립을 지우며 당긴 위치에 영향받지 않는다.
            let removing = tracks[trackIndex].clips.filter { clipIDs.contains($0.id) }.sorted { $0.timelineStart > $1.timelineStart }
            for clip in removing {
                tracks[trackIndex].removeClip(id: clip.id, ripple: ripple)
            }
        }
    }

    /// 재생 헤드 같은 시각에서 클립을 나눈다. 고른 클립이 없으면(`nil`) 그 시각에 걸친 모든 클립을 나눈다.
    mutating func split(at time: CMTime, clipIDs: Set<Clip.ID>?) {
        for index in tracks.indices {
            tracks[index].split(at: time, clipIDs: clipIDs)
        }
    }

    /// 클립을 다른 시각·트랙으로 옮긴다. 삽입이면 원래 자리의 틈을 메우고 새 자리 뒤를 밀며(순서 바꾸기),
    /// 덮어쓰기면 원래 자리를 비우고 새 자리를 덮는다. 종류가 다른 트랙으로는 옮기지 않는다.
    /// `time`은 옮기기 전 화면 기준 시각이다.
    mutating func moveClip(_ clipID: Clip.ID, toTrack trackID: Track.ID, at time: CMTime, mode: PlacementMode) {
        guard let sourceTrackID = self.trackID(containing: clipID),
              var clip = clip(id: clipID),
              let sourceKind = tracks.first(where: { $0.id == sourceTrackID })?.kind,
              tracks.contains(where: { $0.id == trackID && $0.kind == sourceKind })
        else { return }
        let ripple = mode == .insert
        removeClips([clipID], ripple: ripple)
        var destination = CMTimeMaximum(time, .zero)
        // 같은 트랙에서 뒤로 옮기면 틈을 메우며 당겨진 만큼 놓을 시각도 앞으로 온다.
        if ripple, trackID == sourceTrackID, destination >= clip.timelineRange.end {
            destination = destination - clip.sourceRange.duration
        } else if ripple, trackID == sourceTrackID, destination > clip.timelineStart {
            destination = clip.timelineStart
        }
        clip.timelineStart = destination
        place(clip, onTrack: trackID, mode: mode)
    }

    /// 0초와 클립 경계 중 `tolerance` 안에 있는 가장 가까운 시각으로 붙인다. 가까운 경계가 없으면 그대로 돌려준다.
    /// 옮기는 중인 클립 자신의 경계(`excluding`)에는 붙지 않는다.
    func snappedTime(_ time: CMTime, tolerance: CMTime, excluding excludedClipID: Clip.ID? = nil) -> CMTime {
        let edges = [CMTime.zero] + tracks.flatMap(\.clips).filter { $0.id != excludedClipID }.flatMap { [$0.timelineStart, $0.timelineRange.end] }
        let nearest = edges.min { abs(($0 - time).seconds) < abs(($1 - time).seconds) }
        guard let nearest, abs((nearest - time).seconds) <= tolerance.seconds else { return time }
        return nearest
    }
}

// MARK: - MediaAsset

nonisolated extension MediaAsset {
    /// 영상과 이미지는 영상 트랙, 오디오는 오디오 트랙에 놓는다.
    var trackKind: TrackKind {
        kind == .audio ? .audio : .video
    }

    /// 타임라인에 처음 놓을 때의 길이. 이미지는 길이가 없어 정해진 길이를 쓴다.
    var placementDuration: CMTime {
        kind == .image ? Self.stillImageDuration : duration
    }
}
