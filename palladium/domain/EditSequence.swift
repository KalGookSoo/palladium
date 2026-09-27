import Foundation

/// 프로젝트 안의 독립된 편집 결과물 하나(통합본 또는 하이라이트).
///
/// Swift 표준 라이브러리의 `Sequence` 프로토콜과 이름이 겹치지 않도록 `EditSequence`로 짓는다.
nonisolated struct EditSequence {
    /// 시퀀스를 구분하는 고유 식별자.
    let id: UUID
    /// 사용자에게 보이는 시퀀스 이름.
    var name: String
    /// 이 시퀀스에 속한 트랙들.
    var tracks: [Track]
}

extension EditSequence: Identifiable {}
extension EditSequence: Equatable {}
