import OSLog
import SwiftUI

extension FocusedValues {
    /// 저장할 변경이 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var saveProject: (() -> Void)?
    /// 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var importMedia: (() -> Void)?
    /// 내보낼 클립이 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var exportSequence: (() -> Void)?
    /// 클립이 있는 시퀀스가 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var batchExport: (() -> Void)?
    /// 재생 헤드에 그릴 화면이 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var exportStillFrame: (() -> Void)?
    /// 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var importSubtitles: (() -> Void)?
    /// 자막이 있는 편집 창이 앞에 있을 때만 값이 있다.
    @Entry var exportSubtitles: (() -> Void)?
}

struct FileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.saveProject) private var saveProject
    @FocusedValue(\.importMedia) private var importMedia
    @FocusedValue(\.exportSequence) private var exportSequence
    @FocusedValue(\.batchExport) private var batchExport
    @FocusedValue(\.exportStillFrame) private var exportStillFrame
    @FocusedValue(\.importSubtitles) private var importSubtitles
    @FocusedValue(\.exportSubtitles) private var exportSubtitles

    var body: some Commands {
        // 기본 "새 윈도우"는 프로젝트 없이 편집 창을 열기 때문에, 프로젝트 목록(시작 창)을 여는 항목으로 바꾼다.
        CommandGroup(replacing: .newItem) {
            Button("프로젝트 목록 열기") {
                openWindow(id: SceneID.launcher)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        // `.saveItem` 묶음에는 시스템의 "닫기"(⌘W)가 들어 있어 교체하지 않고 뒤에 덧붙인다.
        CommandGroup(after: .saveItem) {
            Button("저장") {
                saveProject?()
            }
            .keyboardShortcut("s")
            .disabled(saveProject == nil)
        }

        CommandGroup(after: .newItem) {
            Button("가져오기…") {
                importMedia?()
            }
            .keyboardShortcut("i")
            .disabled(importMedia == nil)
            Button("내보내기…") {
                exportSequence?()
            }
            .keyboardShortcut("e")
            .disabled(exportSequence == nil)
            Button("여러 시퀀스 내보내기…") {
                batchExport?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(batchExport == nil)
            Button("정지 프레임 저장…") {
                exportStillFrame?()
            }
            .disabled(exportStillFrame == nil)
            Divider()
            Button("자막 가져오기(SRT)…") {
                importSubtitles?()
            }
            .disabled(importSubtitles == nil)
            Button("자막 내보내기(SRT)…") {
                exportSubtitles?()
            }
            .disabled(exportSubtitles == nil)
        }
    }
}
