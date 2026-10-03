import SwiftData
import SwiftUI

@main
struct palladiumApp: App {
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ProjectRecord.self)
        } catch {
            fatalError("프로젝트 저장소를 열 수 없음: \(error)")
        }
    }()

    var body: some Scene {
        // 앱을 켜면 먼저 뜨는 시작 창. 목록에서 프로젝트를 열면 아래 편집 창이 뜨고 이 창은 닫힌다.
        Window("프로젝트", id: SceneID.launcher) {
            ProjectLauncherView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .modelContainer(modelContainer)

        WindowGroup(for: Project.ID.self) { $projectID in
            ProjectWindowView(projectID: projectID)
        }
        .modelContainer(modelContainer)
        .commands {
            FileCommands()
            PanelVisibilityCommands()
            TimelineZoomCommands()
        }
    }
}
