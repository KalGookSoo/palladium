import OSLog
import SwiftData
import SwiftUI

enum SceneID {
    static let launcher = "launcher"
    static let shortcutGuide = "shortcut-guide"
}

/// Xcode의 시작 창처럼 앱을 켜면 먼저 뜨는 프로젝트 목록. 프로젝트를 열면 편집 창을 띄우고 이 창은 닫는다.
struct ProjectLauncherView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var summaries: [ProjectSummary] = []
    @State private var selectedProjectID: Project.ID?
    @State private var isNamingNewProject = false
    @State private var newProjectName = ""
    @State private var errorMessage: String?
    /// 삭제를 확인 중인 프로젝트.
    @State private var projectPendingDeletion: ProjectSummary?

    var body: some View {
        let isConfirmingDeletion = Binding<Bool>(
            get: { projectPendingDeletion != nil },
            set: {
                if !$0 {
                    projectPendingDeletion = nil
                }
            }
        )
        let isShowingError = Binding<Bool>(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )

        Group {
            if summaries.isEmpty {
                ContentUnavailableView(
                    "프로젝트 없음",
                    systemImage: "film.stack",
                    description: Text("새 프로젝트를 만들거나 최근 프로젝트를 여세요")
                )
            } else {
                List(summaries, selection: $selectedProjectID) { summary in
                    ProjectSummaryRow(summary: summary)
                }
                .contextMenu(forSelectionType: Project.ID.self) { projectIDs in
                    if let projectID = projectIDs.first {
                        Button("삭제…", role: .destructive) { askToDelete(projectID) }
                            .keyboardShortcut(.delete, modifiers: [])
                    }
                } primaryAction: { projectIDs in
                    if let projectID = projectIDs.first {
                        openProject(projectID)
                    }
                }
                .onDeleteCommand {
                    if let selectedProjectID {
                        askToDelete(selectedProjectID)
                    }
                }
            }
        }
        .frame(width: 600, height: 420)
        // 목록이 있든 없든 항상 보이도록 창 툴바에 아이콘 버튼으로 둔다. 레이블은 툴팁과 VoiceOver에 쓰인다.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newProjectName = ""
                    isNamingNewProject = true
                } label: {
                    Label(ShortcutGuide.newProject.title, systemImage: "plus")
                }
                .keyboardShortcut("n")
                .help(ShortcutGuide.newProject.helpText)
            }
        }
        .task { reloadSummaries() }
        .alert("새 프로젝트", isPresented: $isNamingNewProject) {
            TextField("프로젝트 이름", text: $newProjectName, prompt: Text(Project.untitledName))
            Button("만들기", action: createProject)
            Button("취소", role: .cancel) {}
        } message: {
            Text("만들면 바로 저장됩니다.")
        }
        .confirmationDialog(
            "\"\(projectPendingDeletion?.name ?? "")\" 프로젝트를 삭제하시겠습니까?",
            isPresented: isConfirmingDeletion,
            presenting: projectPendingDeletion
        ) { summary in
            Button("삭제", role: .destructive) { deleteProject(summary.id) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("삭제한 프로젝트는 되돌릴 수 없습니다. 프로젝트가 참조하던 원본 미디어 파일은 지워지지 않습니다.")
        }
        .alert("오류", isPresented: isShowingError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reloadSummaries() {
        do {
            summaries = try SwiftDataProjectRepository(modelContext: modelContext).projectSummaries()
        } catch {
            Logger.project.error("프로젝트 목록 조회 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "프로젝트 목록을 불러오지 못했습니다."
        }
    }

    private func createProject() {
        do {
            let project = try SwiftDataProjectRepository(modelContext: modelContext).createProject(named: newProjectName)
            openProject(project.id)
        } catch {
            Logger.project.error("프로젝트 생성 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "프로젝트를 만들지 못했습니다."
        }
    }

    private func askToDelete(_ projectID: Project.ID) {
        projectPendingDeletion = summaries.first { $0.id == projectID }
    }

    private func deleteProject(_ projectID: Project.ID) {
        do {
            try SwiftDataProjectRepository(modelContext: modelContext).deleteProject(id: projectID)
            selectedProjectID = nil
            reloadSummaries()
        } catch {
            Logger.project.error("프로젝트 삭제 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "프로젝트를 삭제하지 못했습니다."
        }
    }

    private func openProject(_ projectID: Project.ID) {
        openWindow(value: projectID)
        dismissWindow(id: SceneID.launcher)
    }
}

private struct ProjectSummaryRow: View {
    let summary: ProjectSummary

    var body: some View {
        HStack(spacing: 12) {
            // 썸네일은 필름스트립 생성(#31)과 함께 채우고, 그전까지 아이콘으로 자리를 잡는다.
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44)
            VStack(alignment: .leading) {
                Text(summary.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("원본 \(summary.assetCount)개 · 시퀀스 \(summary.sequenceCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(summary.modifiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProjectLauncherView()
        .modelContainer(for: ProjectRecord.self, inMemory: true)
}
