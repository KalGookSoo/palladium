import CoreMedia
import Foundation

/// Swift 표준 라이브러리의 `Sequence` 프로토콜과 이름이 겹치지 않도록 `EditSequence`로 짓는다.
nonisolated struct EditSequence {
    let id: UUID
    var name: String
    var tracks: [Track]
    var markers: [Marker] = []
}

// MARK: - Queries

nonisolated extension EditSequence {
    /// 가장 늦게 끝나는 클립의 끝 시각. 클립이 없으면 0이다.
    var duration: CMTime {
        tracks
            .flatMap(\.clips)
            .map(\.timelineRange.end)
            .max() ?? .zero
    }
}

nonisolated extension EditSequence: Identifiable {}
nonisolated extension EditSequence: Equatable {}
