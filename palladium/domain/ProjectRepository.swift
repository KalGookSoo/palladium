import Foundation

/// 도메인은 저장소를 이 프로토콜로만 안다. SwiftData 구현은 영속 계층(`palladium/persistence/`)에 있다.
/// 새 프로젝트는 만드는 즉시 저장되고, 이후 내용 변경은 사용자가 저장(`save`)해야 반영된다.
protocol ProjectRepository {
    /// 최근에 수정한 프로젝트가 먼저 온다.
    func projectSummaries() throws -> [ProjectSummary]

    /// 마지막으로 저장한 내용을 돌려준다. 없는 프로젝트면 `nil`이다.
    func project(id: Project.ID) throws -> Project?

    /// 만든 즉시 저장하고, 만든 프로젝트를 돌려준다.
    func createProject(named name: String) throws -> Project

    /// 프로젝트 내용을 통째로 저장하고 수정 시각을 갱신한다. 저장소에 없는 프로젝트면 `ProjectRepositoryError.projectNotFound`.
    func save(_ project: Project) throws

    /// 프로젝트와 그 내용·백업본을 영구히 지운다. 원본 미디어 파일은 건드리지 않는다. 없는 프로젝트면 아무 일도 하지 않는다.
    func deleteProject(id: Project.ID) throws

    // MARK: - 백업본

    /// 마지막 저장 이후에 쓴 백업본이 있으면 돌려준다. 저장보다 오래된 백업본은 없는 것으로 본다.
    func recoverableBackup(for projectID: Project.ID) throws -> ProjectBackup?

    /// 저장하지 않은 변경을 백업본으로 쓴다. 이전 백업본은 덮어쓴다.
    func writeBackup(of project: Project) throws

    /// 백업본을 지운다. 없으면 아무 일도 하지 않는다.
    func deleteBackup(for projectID: Project.ID) throws
}

enum ProjectRepositoryError: Error {
    case projectNotFound(Project.ID)
}
