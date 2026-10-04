import CoreMedia
import Foundation

/// 이미 클립이 있는 자리에 새 클립을 놓는 방식.
nonisolated enum PlacementMode {
    /// 놓는 구간의 기존 클립을 잘라내고 덮는다(기본).
    case overwrite
    /// 놓는 지점 뒤의 클립을 새 클립 길이만큼 뒤로 민다. 놓는 지점에 걸친 클립은 둘로 나눈다.
    case insert
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

    /// 0초와 클립 경계 중 `tolerance` 안에 있는 가장 가까운 시각으로 붙인다. 가까운 경계가 없으면 그대로 돌려준다.
    func snappedTime(_ time: CMTime, tolerance: CMTime) -> CMTime {
        let edges = [CMTime.zero] + tracks.flatMap(\.clips).flatMap { [$0.timelineStart, $0.timelineRange.end] }
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
