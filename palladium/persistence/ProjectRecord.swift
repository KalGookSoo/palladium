import Foundation
import SwiftData

/// 프로젝트의 저장 전용 레코드. 지금은 시작 화면 목록에 필요한 정보만 담고,
/// 원본·시퀀스·클립 같은 내용은 프로젝트 저장/불러오기(#7)에서 별도 레코드로 확장한다.
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var assetCount: Int
    var sequenceCount: Int

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
