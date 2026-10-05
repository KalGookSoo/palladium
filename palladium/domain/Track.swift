import CoreMedia
import Foundation

nonisolated struct Track {
    let id: UUID
    let kind: TrackKind
    var clips: [Clip]
    /// 트랙 전체 소리의 크기(0~1)와 음소거. 클립 음량에 곱해진다(#44).
    var volume = 1.0
    var isMuted = false
}

nonisolated enum TrackKind: String {
    case video
    case audio
}

// MARK: - Queries

nonisolated extension Track {
    /// 앞 클립이 끝나는 순간 다음 클립이 시작하는 맞닿은 배치는 컷 편집의 정상 상태이므로 겹침으로 보지 않는다.
    var hasOverlappingClips: Bool {
        let sortedClips = clips.sorted { $0.timelineStart < $1.timelineStart }
        return zip(sortedClips, sortedClips.dropFirst()).contains { current, next in
            next.timelineStart < current.timelineRange.end
        }
    }
}

nonisolated extension Track: Identifiable {}
nonisolated extension Track: Equatable {}
