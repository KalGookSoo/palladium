import CoreMedia
import Foundation

/// Swift 표준 라이브러리의 `Sequence` 프로토콜과 이름이 겹치지 않도록 `EditSequence`로 짓는다.
nonisolated struct EditSequence {
    let id: UUID
    var name: String
    var tracks: [Track]
    var markers: [Marker] = []
    /// 결과물 시간에 붙는 자막(자막 트랙). 시작 시각 순으로 유지한다(#4).
    var subtitles: [Subtitle] = []
    /// 화면 일부를 가리는 블러·모자이크(#59). 결과물 시간에 붙고, 시퀀스 길이에는 넣지 않는다(가릴 화면이 있을 때만 의미가 있다).
    var masks: [Mask] = []
}

// MARK: - Queries

nonisolated extension EditSequence {
    /// 가장 늦게 끝나는 클립(또는 자막)의 끝 시각. 아무것도 없으면 0이다.
    var duration: CMTime {
        (tracks.flatMap(\.clips).map(\.timelineRange.end) + subtitles.map(\.range.end)).max() ?? .zero
    }
}

nonisolated extension EditSequence: Identifiable {}
nonisolated extension EditSequence: Equatable {}
