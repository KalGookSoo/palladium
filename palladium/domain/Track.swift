import CoreMedia
import Foundation

/// 시퀀스 안에서 클립이 시간순으로 놓이는 레인 하나.
nonisolated struct Track {
    /// 트랙을 구분하는 고유 식별자.
    let id: UUID
    /// 트랙의 종류.
    let kind: TrackKind
    /// 이 트랙에 놓인 클립들.
    var clips: [Clip]
}

/// 트랙의 종류.
nonisolated enum TrackKind {
    /// 영상 트랙.
    case video
    /// 오디오 트랙.
    case audio
}

// MARK: - Queries

extension Track {
    /// 타임라인 구간이 서로 겹치는 클립이 하나라도 있으면 `true`.
    var hasOverlappingClips: Bool {
        let sortedClips = clips.sorted { $0.timelineStart < $1.timelineStart }
        return zip(sortedClips, sortedClips.dropFirst()).contains { current, next in
            next.timelineStart < current.timelineRange.end
        }
    }
}

extension Track: Identifiable {}
extension Track: Equatable {}
