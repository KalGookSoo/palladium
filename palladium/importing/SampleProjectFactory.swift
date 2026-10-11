import Foundation

/// 샘플 프로젝트 둘러보기(#63). 샘플 미디어를 기기에서 만들어(이미 있으면 그대로) "palladium 둘러보기" 프로젝트를 만든다.
/// 원본은 "샘플" 폴더에 넣고 시퀀스는 비워 둔다 — 배치부터 사용자가 해 보게 하기 위해서다. 다시 둘러보면 새 프로젝트를 만든다.
enum SampleProjectFactory {
    static let projectName = "palladium 둘러보기"
    static let folderName = "샘플"

    /// 만든 프로젝트 ID. 샘플을 만들거나 가져오지 못하면 오류를 던진다.
    static func makeTourProject(
        using repository: ProjectRepository,
        progress: TourProgress = .shared,
        directory: URL = SampleMediaGenerator.defaultDirectory
    ) async throws -> Project.ID {
        let urls = try await SampleMediaGenerator.makeAll(in: directory)
        let report = await MediaImporter.importMedia(from: urls, existingAssets: [])
        guard report.failures.isEmpty, !report.imported.isEmpty else {
            throw SampleProjectError.importFailed(report.failures.map(\.message).joined(separator: "\n"))
        }
        var project = try repository.createProject(named: projectName)
        project.assets = report.imported
        project.addFolder(named: folderName)
        project.moveAssets(report.imported.map(\.id), toFolder: project.folders.first?.id)
        try repository.save(project)
        progress.registerTourProject(project.id)
        return project.id
    }
}

enum SampleProjectError: LocalizedError {
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case let .importFailed(message): "샘플 미디어를 가져오지 못했습니다.\n\(message)"
        }
    }
}
