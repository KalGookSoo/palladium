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

extension Project: Identifiable {}
extension Project: Equatable {}
