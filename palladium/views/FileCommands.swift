import OSLog
import SwiftUI

struct FileCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // 기본 "새 윈도우"는 프로젝트 없이 편집 창을 열기 때문에, 프로젝트 목록(시작 창)을 여는 항목으로 바꾼다.
        CommandGroup(replacing: .newItem) {
            Button("프로젝트 목록 열기") {
                openWindow(id: SceneID.launcher)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Button("가져오기…", action: requestMediaImport)
                .keyboardShortcut("i")
            Button("내보내기…", action: requestExport)
                .keyboardShortcut("e")
        }
    }
}

func requestMediaImport() {
    Logger.mediaImport.info("미디어 가져오기 요청: 아직 구현되지 않음")
}

func requestExport() {
    Logger.export.info("내보내기 요청: 아직 구현되지 않음")
}
