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
}

enum ProjectRepositoryError: Error {
    case projectNotFound(Project.ID)
}
