import Foundation
import SwiftData

/// 저장하지 않은 변경의 백업본. 프로젝트마다 최대 하나이며, 내용은 저장본과 같은 하위 레코드 구조를 쓴다.
@Model
final class ProjectBackupRecord {
    @Attribute(.unique) var projectID: UUID
    var name: String
    var backedUpAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MediaAssetRecord.backup) var assets: [MediaAssetRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \MediaFolderRecord.backup) var folders: [MediaFolderRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \SequenceRecord.backup) var sequences: [SequenceRecord] = []

    init(projectID: UUID, name: String, backedUpAt: Date) {
        self.projectID = projectID
        self.name = name
        self.backedUpAt = backedUpAt
    }
}

// MARK: - Mapping

extension ProjectBackupRecord {
    func replaceContent(with project: Project, backedUpAt: Date, in modelContext: ModelContext) {
        ProjectContentRecords(assets: assets, folders: folders, sequences: sequences).delete(in: modelContext)

        let content = ProjectContentRecords(project: project)
        name = project.name
        self.backedUpAt = backedUpAt
        assets = content.assets
        folders = content.folders
        sequences = content.sequences
    }

    func makeBackup() -> ProjectBackup {
        let project = ProjectContentRecords(assets: assets, folders: folders, sequences: sequences)
            .makeProject(id: projectID, name: name)
        return ProjectBackup(project: project, backedUpAt: backedUpAt)
    }
}
