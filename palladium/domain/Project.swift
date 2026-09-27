import Foundation

nonisolated struct Project {
    let id: UUID
    var name: String
    var assets: [MediaAsset]
    var sequences: [EditSequence]

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
    static func makeNew(name: String) -> Project {
        let firstSequence = EditSequence(id: UUID(), name: "시퀀스 1", tracks: [])
        guard let project = Project(name: name, assets: [], sequences: [firstSequence]) else {
            preconditionFailure("시퀀스를 하나 넘겼으므로 Project 생성은 실패할 수 없다")
        }
        return project
    }
}

extension Project: Identifiable {}
extension Project: Equatable {}
