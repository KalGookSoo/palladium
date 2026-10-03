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

    func project(id: Project.ID) throws -> Project? {
        try record(id: id)?.makeProject()
    }

    // MARK: - Commands

    func createProject(named name: String) throws -> Project {
        let project = Project.makeNew(name: name)
        let createdAt = now()
        let record = ProjectRecord(summary: project.summary(createdAt: createdAt, modifiedAt: createdAt))
        modelContext.insert(record)
        record.replaceContent(with: project, modifiedAt: createdAt, in: modelContext)
        try modelContext.save()
        Logger.project.info("프로젝트 생성: \(project.id, privacy: .public)")
        return project
    }

    func save(_ project: Project) throws {
        guard let record = try record(id: project.id) else {
            throw ProjectRepositoryError.projectNotFound(project.id)
        }
        record.replaceContent(with: project, modifiedAt: now(), in: modelContext)
        try modelContext.save()
        Logger.project.notice("프로젝트 저장: \(project.id, privacy: .public)")
    }

    // MARK: - Helpers

    private func record(id: Project.ID) throws -> ProjectRecord? {
        let targetID = id
        var descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
