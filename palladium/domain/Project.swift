import Foundation

/// 가져온 원본 미디어와 시퀀스를 담는 저장 단위.
nonisolated struct Project {
    /// 프로젝트를 구분하는 고유 식별자.
    let id: UUID
    /// 사용자에게 보이는 프로젝트 이름.
    var name: String
    /// 프로젝트로 가져온 원본 미디어들.
    var assets: [MediaAsset]
    /// 프로젝트 안의 편집 결과물들.
    var sequences: [EditSequence]

    /// 프로젝트를 만든다. 시퀀스가 하나도 없으면 만들지 않고 `nil`을 반환한다.
    init?(id: UUID = UUID(), name: String, assets: [MediaAsset], sequences: [EditSequence]) {
        guard !sequences.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.assets = assets
        self.sequences = sequences
    }
}

// MARK: - Factories

extension Project {
    /// 빈 시퀀스 하나로 시작하는 새 프로젝트를 만든다.
    /// - Parameter name: 새 프로젝트의 이름.
    static func makeNew(name: String) -> Project {
        let firstSequence = EditSequence(id: UUID(), name: "시퀀스 1", tracks: [])
        // 시퀀스를 하나 넘기므로 init?은 항상 성공한다.
        return Project(name: name, assets: [], sequences: [firstSequence])!
    }
}

extension Project: Identifiable {}
extension Project: Equatable {}
