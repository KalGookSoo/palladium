import OSLog
import SwiftUI

struct FileCommands: Commands {
    var body: some Commands {
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
