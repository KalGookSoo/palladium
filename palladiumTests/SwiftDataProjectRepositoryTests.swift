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

    @Test("저장한 프로젝트를 다시 불러오면 원본·폴더·시퀀스·트랙·클립·마커가 순서까지 그대로다")
    func savedProjectRoundTrips() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let created = try repository.createProject(named: "샘플")
        let edited = try sampleContent(withID: created.id)

        try repository.save(edited)

        #expect(try repository.project(id: created.id) == edited)
    }

    @Test("다시 저장하면 이전 내용이 남지 않고 새 내용으로 바뀐다")
    func savingAgainReplacesContent() throws {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let created = try repository.createProject(named: "샘플")
        try repository.save(sampleContent(withID: created.id))

        try repository.save(created)

        #expect(try repository.project(id: created.id) == created)
    }

    @Test("저장하면 목록의 수정 시각과 원본·시퀀스 개수가 갱신된다")
    func savingUpdatesSummary() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext) {
            clock = clock.addingTimeInterval(60)
            return clock
        }
        let created = try repository.createProject(named: "샘플")

        try repository.save(sampleContent(withID: created.id))

        let summary = try #require(try repository.projectSummaries().first)
        #expect(summary.modifiedAt == clock)
        #expect(summary.modifiedAt > summary.createdAt)
        #expect(summary.assetCount == 3)
        #expect(summary.sequenceCount == 1)
    }

    @Test("저장소에 없는 프로젝트를 저장하면 오류가 난다")
    func savingUnknownProjectThrows() {
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        #expect(throws: ProjectRepositoryError.self) {
            try repository.save(Project.makeNew(name: "없는 프로젝트"))
        }
    }

    @Test("내용이 저장되기 전 레코드는 빈 시퀀스 하나로 열린다")
    func recordWithoutContentOpensWithEmptySequence() throws {
        let date = Date(timeIntervalSince1970: 0)
        let summary = ProjectSummary(id: UUID(), name: "예전 프로젝트", createdAt: date, modifiedAt: date, assetCount: 0, sequenceCount: 0)
        container.mainContext.insert(ProjectRecord(summary: summary))
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)

        let project = try #require(try repository.project(id: summary.id))
        #expect(project.name == "예전 프로젝트")
        #expect(project.sequences.count == 1)
    }

    // MARK: - Helpers

    /// 샘플 프로젝트의 내용을 주어진 id의 프로젝트로 옮긴다.
    private func sampleContent(withID id: Project.ID) throws -> Project {
        let sample = SampleData.project
        return try #require(Project(id: id, name: sample.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
    }
}
