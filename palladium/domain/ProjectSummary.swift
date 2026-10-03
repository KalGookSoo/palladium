import Foundation

/// 시작 화면 목록에 보여줄 프로젝트 요약. 프로젝트 전체를 불러오지 않고도 목록을 그릴 수 있게 한다.
nonisolated struct ProjectSummary {
    let id: Project.ID
    var name: String
    let createdAt: Date
    var modifiedAt: Date
    var assetCount: Int
    var sequenceCount: Int
}

extension ProjectSummary: Identifiable {}
extension ProjectSummary: Equatable {}
