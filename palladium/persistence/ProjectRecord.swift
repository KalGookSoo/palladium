import Foundation
import SwiftData

/// 프로젝트의 저장 전용 레코드. 목록 정보와 함께 원본·폴더·시퀀스를 하위 레코드로 가진다.
/// 프로젝트를 지우면 하위 레코드도 함께 지워진다(`cascade`).
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var assetCount: Int
    var sequenceCount: Int
    @Relationship(deleteRule: .cascade, inverse: \MediaAssetRecord.project) var assets: [MediaAssetRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \MediaFolderRecord.project) var folders: [MediaFolderRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \SequenceRecord.project) var sequences: [SequenceRecord] = []

    init(summary: ProjectSummary) {
        id = summary.id
        name = summary.name
        createdAt = summary.createdAt
        modifiedAt = summary.modifiedAt
        assetCount = summary.assetCount
        sequenceCount = summary.sequenceCount
    }
}

// MARK: - Queries

extension ProjectRecord {
    var summary: ProjectSummary {
        ProjectSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            assetCount: assetCount,
            sequenceCount: sequenceCount
        )
    }
}
