import Foundation

/// 도메인은 저장소를 이 프로토콜로만 안다. SwiftData 구현은 영속 계층(`palladium/persistence/`)에 있다.
/// 별도의 "저장" 동작은 없다 — 만들거나 바꾸는 즉시 저장된다.
protocol ProjectRepository {
    /// 최근에 수정한 프로젝트가 먼저 온다.
    func projectSummaries() throws -> [ProjectSummary]

    /// 없는 프로젝트면 `nil`이다.
    func project(id: Project.ID) throws -> Project?

    /// 만든 즉시 저장하고, 만든 프로젝트를 돌려준다.
    func createProject(named name: String) throws -> Project
}
