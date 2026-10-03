import OSLog
import SwiftUI

extension FocusedValues {
    /// 저장할 변경이 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var saveProject: (() -> Void)?
}

struct FileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.saveProject) private var saveProject

    var body: some Commands {
        // 기본 "새 윈도우"는 프로젝트 없이 편집 창을 열기 때문에, 프로젝트 목록(시작 창)을 여는 항목으로 바꾼다.
        CommandGroup(replacing: .newItem) {
            Button("프로젝트 목록 열기") {
                openWindow(id: SceneID.launcher)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("저장") {
                saveProject?()
            }
            .keyboardShortcut("s")
            .disabled(saveProject == nil)
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
