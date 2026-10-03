import OSLog
import SwiftData
import SwiftUI

/// 프로젝트 하나를 여는 편집 창. 창이 받은 프로젝트 id로 저장소에서 프로젝트를 불러와 메인 편집 화면을 보여준다.
struct ProjectWindowView: View {
    /// 창 복원 등으로 id 없이 열리면 `nil`이다.
    let projectID: Project.ID?
    @Environment(\.modelContext) private var modelContext
    @State private var project: Project?
    @State private var isMissing = false

    var body: some View {
        if let project {
            MainWindowView(project: project)
        } else if isMissing || projectID == nil {
            ContentUnavailableView(
                "프로젝트를 찾을 수 없음",
                systemImage: "questionmark.folder",
                description: Text("파일 메뉴의 \"프로젝트 목록 열기\"(⇧⌘1)에서 프로젝트를 다시 여세요")
            )
            .frame(minWidth: 480, minHeight: 320)
        } else {
            ProgressView()
                .frame(minWidth: 480, minHeight: 320)
                .task { loadProject() }
        }
    }

    private func loadProject() {
        guard let projectID else { return }
        do {
            project = try SwiftDataProjectRepository(modelContext: modelContext).project(id: projectID)
            isMissing = project == nil
        } catch {
            Logger.project.error("프로젝트 불러오기 실패: \(error.localizedDescription, privacy: .public)")
            isMissing = true
        }
    }
}
