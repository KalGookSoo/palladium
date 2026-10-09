import SwiftData
import SwiftUI

@main
struct palladiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ProjectRecord.self, ProjectBackupRecord.self)
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

        Settings {
            SettingsView()
        }

        Window("palladium 도움말", id: SceneID.help) {
            HelpView()
        }
        .windowResizability(.contentSize)

        WindowGroup(for: Project.ID.self) { $projectID in
            ProjectWindowView(projectID: projectID)
        }
        .modelContainer(modelContainer)
        .commands {
            FileCommands()
            MediaCommands()
            PanelVisibilityCommands()
            TimelineZoomCommands()
            HelpCommands()
            #if DEBUG
                DebugCommands()
            #endif
        }

        // 클립 편집 창(#85). 프로젝트마다 하나이고 프로젝트 창이 닫히면 함께 닫힌다. 프로젝트 창이 없으면 쓸 수 없어 복원하지 않는다.
        WindowGroup("클립 편집", id: SceneID.clipEdit, for: ClipEditWindowValue.self) { $value in
            ClipEditWindowView(value: value)
        }
        .defaultSize(width: 960, height: 680)
        .restorationBehavior(.disabled)
    }
}
