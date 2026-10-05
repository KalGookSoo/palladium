import CoreMedia
import Foundation

// MARK: - Clip

nonisolated extension Clip {
    /// 타임라인 구간 `[start, end)`에 해당하는 부분만 남긴 클립. 겹치는 부분이 없으면 `nil`.
    /// 앞부분을 잘라내면 원본 구간의 시작도 같은 만큼 뒤로 간다.
    func portion(from start: CMTime, to end: CMTime, id: UUID) -> Clip? {
        let clippedStart = CMTimeMaximum(start, timelineStart)
        let clippedEnd = CMTimeMinimum(end, timelineRange.end)
        guard clippedStart < clippedEnd else { return nil }
        let sourceStart = sourceRange.start + (clippedStart - timelineStart)
        var portion = Clip(
            id: id,
            assetID: assetID,
            sourceRange: CMTimeRange(start: sourceStart, duration: clippedEnd - clippedStart),
            timelineStart: clippedStart
        )
        // 나눈 조각도 같은 위치·크기·불투명도로 그린다.
        portion?.transform = transform
        return portion
    }
}

// MARK: - Track

nonisolated extension Track {
    /// 클립을 넣을 지점. 클립 안에 떨어지면 앞쪽 절반은 그 클립 앞 경계, 뒤쪽 절반은 뒤 경계로 옮긴다.
    /// 클립 사이 틈이나 맨 뒤라면 그 시각 그대로다. 삽입은 클립을 자동으로 나누지 않기 위함이다.
    func insertionPoint(for time: CMTime) -> CMTime {
        guard let clip = clips.first(where: { $0.timelineStart < time && time < $0.timelineRange.end }) else {
            return CMTimeMaximum(time, .zero)
        }
        let middle = clip.timelineStart + CMTimeMultiplyByRatio(clip.sourceRange.duration, multiplier: 1, divisor: 2)
        return time < middle ? clip.timelineStart : clip.timelineRange.end
    }

    /// 클립을 경계(또는 틈)에 넣고, 뒤 클립과 겹치면 겹치는 만큼 뒤 클립들을 뒤로 민다. 기존 클립은 나누지 않는다.
    mutating func insert(_ clip: Clip) {
        var inserted = clip
        let point = insertionPoint(for: clip.timelineStart)
        inserted.timelineStart = point
        let nextStart = clips.filter { $0.timelineStart >= point }.map(\.timelineStart).min()
        let shift = nextStart.map { CMTimeMaximum(.zero, inserted.timelineRange.end - $0) } ?? .zero
        for index in clips.indices where clips[index].timelineStart >= point {
            clips[index].timelineStart = clips[index].timelineStart + shift
        }
        clips.append(inserted)
        clips.sort { $0.timelineStart < $1.timelineStart }
    }

    /// 클립의 원본 구간을 바꾼다(리플 트림). 클립의 타임라인 시작은 그대로 두고, 길이가 바뀐 만큼 뒤 클립들을 당기거나 민다.
    mutating func setSourceRange(_ range: CMTimeRange, forClip clipID: Clip.ID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }), range.duration > .zero else { return }
        let oldEnd = clips[index].timelineRange.end
        let change = range.duration - clips[index].sourceRange.duration
        clips[index].sourceRange = range
        for other in clips.indices where other != index && clips[other].timelineStart >= oldEnd {
            clips[other].timelineStart = clips[other].timelineStart + change
        }
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
            guard clip.canSplit(at: time, clipIDs: clipIDs) else { return [clip] }
            return [
                clip.portion(from: clip.timelineStart, to: time, id: clip.id),
                clip.portion(from: time, to: clip.timelineRange.end, id: UUID()),
            ].compactMap(\.self)
        }
    }
}

/// 트림할 클립 끝.
nonisolated enum ClipEdge {
    case start
    case end
}

nonisolated extension Clip {
    /// 트림해도 남는 가장 짧은 길이(30fps 한 프레임).
    static let minimumDuration = CMTime(value: 1, timescale: 30)

    /// 원본 구간을 `start`~`end`로 바꾸되 원본 범위 안으로 맞춘다. `sourceDuration`이 `nil`이면(이미지) 길이 제한 없이 늘리고,
    /// 원본 시작은 항상 0이다.
    func clampedSourceRange(start: CMTime, end: CMTime, sourceDuration: CMTime?) -> CMTimeRange {
        guard let sourceDuration else {
            return CMTimeRange(start: .zero, duration: CMTimeMaximum(end - start, Self.minimumDuration))
        }
        let clampedEnd = CMTimeMinimum(CMTimeMaximum(end, Self.minimumDuration), sourceDuration)
        let clampedStart = CMTimeMinimum(CMTimeMaximum(start, .zero), clampedEnd - Self.minimumDuration)
        return CMTimeRange(start: clampedStart, end: clampedEnd)
    }

    /// 한쪽 끝을 `delta`만큼 옮긴 원본 구간. 앞 끝을 오른쪽(+)으로 옮기면 앞부분이 잘리고, 뒤 끝을 오른쪽으로 옮기면 길어진다.
    func trimmedSourceRange(edge: ClipEdge, by delta: CMTime, sourceDuration: CMTime?) -> CMTimeRange {
        switch edge {
        case .start:
            if sourceDuration == nil {
                return clampedSourceRange(start: .zero, end: sourceRange.duration - delta, sourceDuration: nil)
            }
            return clampedSourceRange(start: sourceRange.start + delta, end: sourceRange.end, sourceDuration: sourceDuration)
        case .end:
            return clampedSourceRange(start: sourceRange.start, end: sourceRange.end + delta, sourceDuration: sourceDuration)
        }
    }

    func canSplit(at time: CMTime, clipIDs: Set<Clip.ID>?) -> Bool {
        (clipIDs?.contains(id) ?? true) && timelineStart < time && time < timelineRange.end
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

    /// `time`에 마커를 둔다. 이름이 비어 있으면 "마커 N"(N은 추가 후 개수). 마커는 시각 순으로 유지한다.
    @discardableResult
    mutating func addMarker(at time: CMTime, named name: String = "") -> Marker.ID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = Marker(id: UUID(), time: CMTimeMaximum(time, .zero), name: trimmedName.isEmpty ? "마커 \(markers.count + 1)" : trimmedName)
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        return marker.id
    }

    /// 앞뒤 공백을 빼고, 비어 있으면 바꾸지 않는다.
    mutating func renameMarker(_ markerID: Marker.ID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = markers.firstIndex(where: { $0.id == markerID }) else { return }
        markers[index].name = trimmedName
    }

    mutating func removeMarker(_ markerID: Marker.ID) {
        markers.removeAll { $0.id == markerID }
    }

    /// 비어 있는 트랙만 지운다. 클립이 있는 트랙을 지우면 편집 내용을 잃기 쉬워 막는다.
    mutating func removeTrack(_ trackID: Track.ID) {
        tracks.removeAll { $0.id == trackID && $0.clips.isEmpty }
    }

    /// `rowIndex`번째 행에 가장 가까운 `kind` 트랙. 그런 트랙이 없으면 `nil`.
    /// 놓는 위치가 트랙 사이나 아래 빈 곳이어도 새 트랙을 만들지 않고 가까운 트랙에 넣기 위함이다.
    func nearestTrackID(kind: TrackKind, toRow rowIndex: Int) -> Track.ID? {
        tracks.indices
            .filter { tracks[$0].kind == kind }
            .min { abs($0 - rowIndex) < abs($1 - rowIndex) }
            .map { tracks[$0].id }
    }

    /// 클립을 트랙의 경계(또는 틈)에 넣고 뒤 클립을 민다. 없는 트랙이면 아무것도 하지 않는다.
    mutating func place(_ clip: Clip, onTrack trackID: Track.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].insert(clip)
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

    /// 클립이 있는 트랙에서 원본 구간을 바꾼다(리플 트림).
    mutating func setSourceRange(_ range: CMTimeRange, forClip clipID: Clip.ID) {
        for index in tracks.indices where tracks[index].clips.contains(where: { $0.id == clipID }) {
            tracks[index].setSourceRange(range, forClip: clipID)
        }
    }

    /// 그 시각에서 나눌 클립이 있는지. 메뉴를 비활성화하는 데 쓴다.
    func canSplit(at time: CMTime, clipIDs: Set<Clip.ID>?) -> Bool {
        tracks.contains { $0.clips.contains { $0.canSplit(at: time, clipIDs: clipIDs) } }
    }

    /// 재생 헤드 같은 시각에서 클립을 나눈다. 고른 클립이 없으면(`nil`) 그 시각에 걸친 모든 클립을 나눈다.
    mutating func split(at time: CMTime, clipIDs: Set<Clip.ID>?) {
        for index in tracks.indices {
            tracks[index].split(at: time, clipIDs: clipIDs)
        }
    }

    /// 클립을 다른 시각·트랙으로 옮긴다. 원래 자리의 틈을 메우고(뒤 클립을 당김) 새 자리 경계에 넣어 뒤 클립을 민다.
    /// 같은 트랙에서는 순서 바꾸기가 된다. 종류가 다른 트랙으로는 옮기지 않는다. `time`은 옮기기 전 화면 기준 시각이다.
    mutating func moveClip(_ clipID: Clip.ID, toTrack trackID: Track.ID, at time: CMTime) {
        guard let sourceTrackID = self.trackID(containing: clipID),
              var clip = clip(id: clipID),
              let sourceKind = tracks.first(where: { $0.id == sourceTrackID })?.kind,
              tracks.contains(where: { $0.id == trackID && $0.kind == sourceKind })
        else { return }
        removeClips([clipID], ripple: true)
        var destination = CMTimeMaximum(time, .zero)
        // 같은 트랙에서 뒤로 옮기면 틈을 메우며 당겨진 만큼 놓을 시각도 앞으로 온다.
        if trackID == sourceTrackID, destination >= clip.timelineRange.end {
            destination = destination - clip.sourceRange.duration
        } else if trackID == sourceTrackID, destination > clip.timelineStart {
            destination = clip.timelineStart
        }
        clip.timelineStart = destination
        place(clip, onTrack: trackID)
    }

    /// 길이 `duration`인 클립을 `start`에 놓으려 할 때, 클립의 앞 끝이나 뒤 끝이 `tolerance` 안의 경계
    /// (0초, 다른 클립의 앞뒤 끝, `extraEdges` — 재생 헤드 등)에 닿으면 그 경계에 붙인 시작 시각을 돌려준다(자석처럼 붙기).
    /// 옮기는 중인 클립 자신(`excluding`)의 경계에는 붙지 않는다.
    func snappedStart(
        _ start: CMTime,
        duration: CMTime,
        tolerance: CMTime,
        excluding excludedClipID: Clip.ID? = nil,
        extraEdges: [CMTime] = []
    ) -> CMTime {
        let edges = [CMTime.zero] + extraEdges
            + tracks.flatMap(\.clips).filter { $0.id != excludedClipID }.flatMap { [$0.timelineStart, $0.timelineRange.end] }
        let candidates = edges.flatMap { [$0, $0 - duration] }.filter { $0 >= .zero }
        let nearest = candidates.min { abs(($0 - start).seconds) < abs(($1 - start).seconds) }
        guard let nearest, abs((nearest - start).seconds) <= tolerance.seconds else { return CMTimeMaximum(start, .zero) }
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

    /// 클립이 원본에서 쓸 수 있는 길이. 이미지는 길이 제한이 없어 `nil`.
    var trimmableDuration: CMTime? {
        kind == .image ? nil : duration
    }

    /// 이 원본 전체를 `time`에 놓는 새 클립. 길이가 0이면 `nil`.
    func makeClip(at time: CMTime) -> Clip? {
        Clip(assetID: id, sourceRange: CMTimeRange(start: .zero, duration: placementDuration), timelineStart: CMTimeMaximum(time, .zero))
    }
}
