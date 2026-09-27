import Foundation

/// Swift 표준 라이브러리의 `Sequence` 프로토콜과 이름이 겹치지 않도록 `EditSequence`로 짓는다.
nonisolated struct EditSequence {
    let id: UUID
    var name: String
    var tracks: [Track]
}

extension EditSequence: Identifiable {}
extension EditSequence: Equatable {}
