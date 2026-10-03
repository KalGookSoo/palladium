import OSLog
import SwiftData
import SwiftUI

/// 프로젝트 하나를 여는 편집 창. 창이 받은 프로젝트 id로 저장소에서 프로젝트를 불러와 메인 편집 화면을 보여준다.
/// 마지막 저장 이후의 백업본이 있으면(비정상 종료) 편집 화면을 보여주기 전에 복구할지 묻는다.
struct ProjectWindowView: View {
    /// 창 복원 등으로 id 없이 열리면 `nil`이다.
    let projectID: Project.ID?
    @Environment(\.modelContext) private var modelContext
    @State private var project: Project?
    @State private var isMissing = false
    @State private var pendingBackup: ProjectBackup?
    @State private var recoveredContent: Project?
    @State private var hasResolvedBackup = false

    var body: some View {
        let isAskingToRecover = Binding<Bool>(
            get: { pendingBackup != nil },
            set: { _ in }
        )

        if let project, hasResolvedBackup {
            MainWindowView(project: project, recoveredContent: recoveredContent)
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
                .alert("저장하지 않은 변경 사항이 있습니다", isPresented: isAskingToRecover, presenting: pendingBackup) { backup in
                    Button("복구") { recover(backup) }
                    Button("버리기", role: .destructive) { discardBackup() }
                } message: { backup in
                    Text("\(backup.backedUpAt.formatted(date: .abbreviated, time: .shortened))에 백업된 변경을 복구하시겠습니까? 복구한 내용은 저장해야 반영됩니다.")
                }
        }
    }

    private func loadProject() {
        guard let projectID else { return }
        let repository = SwiftDataProjectRepository(modelContext: modelContext)
        do {
            project = try repository.project(id: projectID)
            isMissing = project == nil
            pendingBackup = try repository.recoverableBackup(for: projectID)
            hasResolvedBackup = pendingBackup == nil
        } catch {
            Logger.project.error("프로젝트 불러오기 실패: \(error.localizedDescription, privacy: .public)")
            isMissing = true
        }
    }

    private func recover(_ backup: ProjectBackup) {
        recoveredContent = backup.project
        pendingBackup = nil
        hasResolvedBackup = true
    }

    private func discardBackup() {
        if let projectID {
            do {
                try SwiftDataProjectRepository(modelContext: modelContext).deleteBackup(for: projectID)
            } catch {
                Logger.project.error("백업본 삭제 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        pendingBackup = nil
        hasResolvedBackup = true
    }
}
