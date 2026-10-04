import Foundation

nonisolated struct Project {
    let id: UUID
    var name: String
    var assets: [MediaAsset]
    var folders: [MediaFolder]
    var sequences: [EditSequence]

    init?(id: UUID = UUID(), name: String, assets: [MediaAsset], folders: [MediaFolder] = [], sequences: [EditSequence]) {
        guard !sequences.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.assets = assets
        self.folders = folders
        self.sequences = sequences
    }
}

// MARK: - Factories

extension Project {
    static let untitledName = "제목 없는 프로젝트"

    /// 이름이 비어 있거나 공백뿐이면 `untitledName`을 쓴다.
    static func makeNew(id: UUID = UUID(), name: String) -> Project {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSequence = EditSequence(id: UUID(), name: "시퀀스 1", tracks: [])
        guard let project = Project(
            id: id,
            name: trimmedName.isEmpty ? untitledName : trimmedName,
            assets: [],
            sequences: [firstSequence]
        ) else {
            preconditionFailure("시퀀스를 하나 넘겼으므로 Project 생성은 실패할 수 없다")
        }
        return project
    }
}

// MARK: - Queries

extension Project {
    /// 프로젝트에 없는 원본을 가리키는 ID는 건너뛴다.
    func assets(in folder: MediaFolder) -> [MediaAsset] {
        folder.assetIDs.compactMap { assetID in
            assets.first { $0.id == assetID }
        }
    }

    var unfiledAssets: [MediaAsset] {
        let filedAssetIDs = Set(folders.flatMap(\.assetIDs))
        return assets.filter { !filedAssetIDs.contains($0.id) }
    }

    func summary(createdAt: Date, modifiedAt: Date) -> ProjectSummary {
        ProjectSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            assetCount: assets.count,
            sequenceCount: sequences.count
        )
    }
}

// MARK: - Commands

nonisolated extension Project {
    /// 빈 시퀀스를 끝에 추가한다. 이름이 비어 있으면 "시퀀스 N"(N은 추가 후 개수)으로 짓는다. 원본은 모든 시퀀스가 함께 쓴다.
    @discardableResult
    mutating func addSequence(named name: String) -> EditSequence.ID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sequence = EditSequence(id: UUID(), name: trimmedName.isEmpty ? "시퀀스 \(sequences.count + 1)" : trimmedName, tracks: [])
        sequences.append(sequence)
        return sequence.id
    }

    /// 앞뒤 공백을 빼고, 비어 있으면 바꾸지 않는다.
    mutating func renameSequence(_ sequenceID: EditSequence.ID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = sequences.firstIndex(where: { $0.id == sequenceID }) else { return }
        sequences[index].name = trimmedName
    }

    /// 시퀀스가 최소 하나는 있어야 하므로 마지막 남은 시퀀스는 지우지 않는다. 원본은 그대로 남는다.
    mutating func deleteSequence(_ sequenceID: EditSequence.ID) {
        guard sequences.count > 1 else { return }
        sequences.removeAll { $0.id == sequenceID }
    }
}

nonisolated extension Project: Identifiable {}
nonisolated extension Project: Equatable {}
