import Foundation
@testable import palladium
import SwiftData
import Testing

/// 저장소는 앱 타깃의 기본 격리(MainActor)를 따르므로 테스트도 MainActor에서 실행한다.
@MainActor
struct SwiftDataProjectRepositoryTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test("저장된 프로젝트가 없으면 목록이 비어 있다")
    func emptyRepositoryHasNoSummaries() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        #expect(try repository.projectSummaries().isEmpty)
    }

    @Test("만든 프로젝트는 바로 목록에 나타난다")
    func createdProjectAppearsInSummaries() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let project = try repository.createProject(named: "여행 브이로그")

        let summaries = try repository.projectSummaries()
        #expect(summaries.map(\.id) == [project.id])
        #expect(summaries.first?.name == "여행 브이로그")
        #expect(summaries.first?.assetCount == 0)
        #expect(summaries.first?.sequenceCount == 1)
    }

    @Test("목록은 최근에 수정한 프로젝트가 먼저 온다")
    func summariesAreSortedByRecentModification() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext) {
            clock = clock.addingTimeInterval(60)
            return clock
        }
        let older = try repository.createProject(named: "먼저 만든 프로젝트")
        let newer = try repository.createProject(named: "나중에 만든 프로젝트")

        #expect(try repository.projectSummaries().map(\.id) == [newer.id, older.id])
    }

    @Test("id로 프로젝트를 다시 불러오면 같은 id와 이름을 가진다")
    func projectCanBeLoadedByID() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let created = try repository.createProject(named: "여행 브이로그")

        let loaded = try #require(try repository.project(id: created.id))
        #expect(loaded.id == created.id)
        #expect(loaded.name == "여행 브이로그")
    }

    @Test("없는 id로 불러오면 nil이다")
    func unknownProjectIsNil() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        #expect(try repository.project(id: UUID()) == nil)
    }
}
