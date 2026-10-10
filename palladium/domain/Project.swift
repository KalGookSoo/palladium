import CoreMedia
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
        // 여러 줄을 함께 끌면 줄마다 같은 원본 목록이 와서 ID가 겹친다(#86). 처음 나온 순서로 하나씩만 옮긴다.
        var seen = Set<MediaAsset.ID>()
        let movingIDs = assetIDs.filter { assetID in assets.contains { $0.id == assetID } && seen.insert(assetID).inserted }
        for index in folders.indices {
            folders[index].assetIDs.removeAll { movingIDs.contains($0) }
        }
        guard let folderID, let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let insertIndex = beforeAssetID.flatMap { folders[folderIndex].assetIDs.firstIndex(of: $0) } ?? folders[folderIndex].assetIDs.endIndex
        folders[folderIndex].assetIDs.insert(contentsOf: movingIDs, at: insertIndex)
    }

    /// 파생 항목이 쓰는 구간을 바꾼다(#81, 클립 편집 창의 "적용"). 원본 범위 안으로 맞추고, 원본 전체가 되면 구간을 없앤다.
    /// `crop`이 있으면 크롭(#85)도 범위로 맞춰 함께 바꾼다. 원본 항목(파생이 아닌 항목)은 바꾸지 않는다.
    mutating func setUsedRange(_ range: CMTimeRange, crop: ClipCrop? = nil, for assetID: MediaAsset.ID) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }), assets[index].isDerived, assets[index].isTrimmable else { return }
        let duration = assets[index].duration
        let clamped = TrimRange.clamped(start: range.start, end: range.end, sourceDuration: duration)
        assets[index].usedRange = clamped.start == .zero && clamped.end == duration ? nil : clamped
        if var crop {
            crop.clamp()
            assets[index].crop = crop
        }
    }

    /// 파생 항목 이름: 처음 원본 이름에 구간을 붙인다(예: "윈드밀1 (0:02.0–0:07.0).mov"). 같은 이름이 있으면 파일 저장처럼 " (1)"·" (2)"…를 붙인다.
    /// 파생 항목에서 또 만들어도 처음 원본 이름을 기준으로 해 이름이 겹겹이 쌓이지 않는다.
    func derivedAssetName(from source: MediaAsset, range: CMTimeRange) -> String {
        let rootName = assets.first { $0.id == source.mediaKey }?.name ?? source.name
        let stem = (rootName as NSString).deletingPathExtension
        let pathExtension = (rootName as NSString).pathExtension
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let label = TimelineScale(pointsPerSecond: 40)
        let base = "\(stem) (\(label.timeLabel(for: range.start))–\(label.timeLabel(for: range.end)))"
        let names = Set(assets.map(\.name))
        var candidate = base + suffix
        var number = 1
        while names.contains(candidate) {
            candidate = "\(base) (\(number))\(suffix)"
            number += 1
        }
        return candidate
    }

    /// 같은 파일을 가리키는 파생 항목을 `afterAssetID` 바로 뒤(같은 폴더)에 구간·크롭(#85)과 함께 추가한다(#81). 이름은 `derivedAssetName` 규칙이다.
    /// 파일을 복사하지 않고, 썸네일·파형·프록시는 처음 원본 것을 같이 쓴다. 원본이 없거나 이미지면 `nil`.
    mutating func addDerivedAsset(from assetID: MediaAsset.ID, usedRange: CMTimeRange, crop: ClipCrop = ClipCrop(), after afterAssetID: MediaAsset.ID) -> MediaAsset.ID? {
        guard let source = assets.first(where: { $0.id == assetID }), source.isTrimmable,
              let assetIndex = assets.firstIndex(where: { $0.id == afterAssetID })
        else { return nil }
        let range = TrimRange.clamped(start: usedRange.start, end: usedRange.end, sourceDuration: source.duration)
        var derived = MediaAsset(
            id: UUID(), name: derivedAssetName(from: source, range: range), sourceURL: source.sourceURL, kind: source.kind,
            duration: source.duration, bookmarkData: source.bookmarkData, colorLabel: source.colorLabel, tags: source.tags
        )
        derived.sourceAssetID = source.mediaKey
        assets.insert(derived, at: assetIndex + 1)
        setUsedRange(range, crop: crop, for: derived.id)
        if let folderIndex = folders.firstIndex(where: { $0.assetIDs.contains(afterAssetID) }),
           let position = folders[folderIndex].assetIDs.firstIndex(of: afterAssetID)
        {
            folders[folderIndex].assetIDs.insert(derived.id, at: position + 1)
        }
        return derived.id
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
