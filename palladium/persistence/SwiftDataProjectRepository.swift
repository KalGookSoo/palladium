import Foundation
import OSLog
import SwiftData

final class SwiftDataProjectRepository: ProjectRepository {
    private let modelContext: ModelContext
    private let now: () -> Date

    /// `now`는 테스트에서 시각을 고정하려고 주입한다.
    init(modelContext: ModelContext, now: @escaping () -> Date = { .now }) {
        self.modelContext = modelContext
        self.now = now
    }

    // MARK: - Queries

    func projectSummaries() throws -> [ProjectSummary] {
        let descriptor = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.summary)
    }

    /// 프로젝트 내용은 아직 저장하지 않으므로(#7), 저장된 id·이름으로 빈 프로젝트를 만들어 돌려준다.
    func project(id: Project.ID) throws -> Project? {
        let targetID = id
        var descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return Project.makeNew(id: record.id, name: record.name)
    }

    // MARK: - Commands

    func createProject(named name: String) throws -> Project {
        let project = Project.makeNew(name: name)
        let createdAt = now()
        modelContext.insert(ProjectRecord(summary: project.summary(createdAt: createdAt, modifiedAt: createdAt)))
        try modelContext.save()
        Logger.project.info("프로젝트 생성: \(project.id, privacy: .public)")
        return project
    }
}
