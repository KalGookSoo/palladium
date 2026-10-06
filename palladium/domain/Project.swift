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

nonisolated extension Project {
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

nonisolated extension Project {
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

    /// 미디어 패널에 빈 폴더를 끝에 추가한다. 이름이 비어 있으면 "새 폴더". 폴더 안에 폴더는 두지 않는다(한 단계).
    @discardableResult
    mutating func addFolder(named name: String) -> MediaFolder.ID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = MediaFolder(id: UUID(), name: trimmedName.isEmpty ? "새 폴더" : trimmedName, assetIDs: [])
        folders.append(folder)
        return folder.id
    }

    /// 앞뒤 공백을 빼고, 비어 있으면 바꾸지 않는다.
    mutating func renameFolder(_ folderID: MediaFolder.ID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = trimmedName
    }

    /// 폴더만 지운다. 안에 있던 원본은 프로젝트에 남아 "분류 안 됨"으로 돌아간다.
    mutating func deleteFolder(_ folderID: MediaFolder.ID) {
        folders.removeAll { $0.id == folderID }
    }

    /// 원본을 폴더로 옮긴다. 원본은 한 폴더에만 속하므로 다른 폴더에서는 빠진다. `folderID`가 `nil`이면 "분류 안 됨"으로 뺀다.
    /// `beforeAssetID`가 같은 폴더에 있으면 그 앞에, 아니면 폴더 끝에 넣는다(폴더 안 순서 바꾸기에도 쓴다).
    mutating func moveAssets(_ assetIDs: [MediaAsset.ID], toFolder folderID: MediaFolder.ID?, before beforeAssetID: MediaAsset.ID? = nil) {
        let movingIDs = assetIDs.filter { assetID in assets.contains { $0.id == assetID } }
        for index in folders.indices {
            folders[index].assetIDs.removeAll { movingIDs.contains($0) }
        }
        guard let folderID, let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let insertIndex = beforeAssetID.flatMap { folders[folderIndex].assetIDs.firstIndex(of: $0) } ?? folders[folderIndex].assetIDs.endIndex
        folders[folderIndex].assetIDs.insert(contentsOf: movingIDs, at: insertIndex)
    }

    /// 원본을 프로젝트에서 뺀다(#60). 폴더에서도 빼고, 그 원본을 쓰는 모든 시퀀스의 클립도 함께 지운다.
    /// 지운 클립 자리는 빈 틈으로 둔다(뒤 클립·자막·마스크와 시간이 어긋나지 않게). 디스크의 파일은 건드리지 않는다.
    mutating func deleteAssets(_ assetIDs: Set<MediaAsset.ID>) {
        assets.removeAll { assetIDs.contains($0.id) }
        for index in folders.indices {
            folders[index].assetIDs.removeAll { assetIDs.contains($0) }
        }
        for index in sequences.indices {
            let clipIDs = sequences[index].tracks.flatMap(\.clips).filter { assetIDs.contains($0.assetID) }.map(\.id)
            sequences[index].removeClips(Set(clipIDs), ripple: false)
        }
    }

    /// 원본을 쓰는 클립 수와 그 클립이 있는 시퀀스 이름(프로젝트 순서). 지우기 전 확인 창에 쓴다.
    func clipUsage(of assetIDs: Set<MediaAsset.ID>) -> (clipCount: Int, sequenceNames: [String]) {
        var clipCount = 0
        var sequenceNames: [String] = []
        for sequence in sequences {
            let count = sequence.tracks.flatMap(\.clips).filter { assetIDs.contains($0.assetID) }.count
            if count > 0 {
                clipCount += count
                sequenceNames.append(sequence.name)
            }
        }
        return (clipCount, sequenceNames)
    }

    /// 시퀀스가 최소 하나는 있어야 하므로 마지막 남은 시퀀스는 지우지 않는다. 원본은 그대로 남는다.
    mutating func deleteSequence(_ sequenceID: EditSequence.ID) {
        guard sequences.count > 1 else { return }
        sequences.removeAll { $0.id == sequenceID }
    }
}

nonisolated extension Project: Identifiable {}
nonisolated extension Project: Equatable {}
