import OSLog
import SwiftUI

/// 파일 > ⌘S 자리의 항목(#92). 앞에 있는 창이 이름과 동작을 정한다:
/// 프로젝트 창은 "저장"(프로젝트 저장), 클립 편집 창은 "적용"(원본 항목이면 "새 항목으로 저장").
struct SaveCommand {
    let title: String
    let perform: () -> Void

    /// 해낸 뒤 잠깐 띄울 알림 문구(#96). 예: "저장됨", "적용됨", "새 항목으로 저장됨".
    var doneMessage: String {
        "\(title)됨"
    }
}

extension FocusedValues {
    /// 저장(적용)할 변경이 있는 창이 앞에 있을 때만 값이 있다.
    @Entry var saveCommand: SaveCommand?
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
    @FocusedValue(\.saveCommand) private var saveCommand
    @FocusedValue(\.importMedia) private var importMedia
    @FocusedValue(\.exportSequence) private var exportSequence
    @FocusedValue(\.batchExport) private var batchExport
    @FocusedValue(\.exportStillFrame) private var exportStillFrame
    @FocusedValue(\.importSubtitles) private var importSubtitles
    @FocusedValue(\.exportSubtitles) private var exportSubtitles
    @FocusedValue(\.newSequence) private var newSequence
    @FocusedValue(\.newMediaFolder) private var newMediaFolder
    @FocusedValue(\.newMediaFolderWithSelection) private var newMediaFolderWithSelection
    @FocusedValue(\.revealAssetsInFinder) private var revealAssetsInFinder

    var body: some Commands {
        // 기본 "새 윈도우"는 프로젝트 없이 편집 창을 열기 때문에, 프로젝트 목록(시작 창)을 여는 항목으로 바꾼다.
        CommandGroup(replacing: .newItem) {
            Button("프로젝트 목록 열기") {
                openWindow(id: SceneID.launcher)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            // 프로젝트 창에서 ⌘N은 새 시퀀스다(#64, Premiere와 같음). 시작 창에서는 그 창의 "새 프로젝트" 버튼이 ⌘N을 먼저 받는다.
            Button(ShortcutGuide.newSequence.title) {
                newSequence?()
            }
            .keyboardShortcut("n")
            .disabled(newSequence == nil)
            // 미디어 패널에 포커스가 있을 때만(#110, Finder와 같은 키).
            Button(ShortcutGuide.newMediaFolder.title) {
                newMediaFolder?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(newMediaFolder == nil)
            Button(ShortcutGuide.newFolderWithSelection.title) {
                newMediaFolderWithSelection?()
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(newMediaFolderWithSelection == nil)
        }

        // 저장은 보이는 이 묶음에 둔다. 문서 앱이 아니라 시스템 저장 항목이 없어, 그 뒤(`after: .saveItem`)에 붙이면
        // 메뉴에 나타나지 않았다(#92). "닫기"(⌘W)가 든 `.saveItem` 묶음은 건드리지 않는다.
        CommandGroup(after: .newItem) {
            Button(saveCommand?.title ?? "저장") {
                saveCommand?.perform()
            }
            .keyboardShortcut("s")
            .disabled(saveCommand == nil)
            Divider()
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
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(exportStillFrame == nil)
            Divider()
            Button(ShortcutGuide.revealInFinder.title) {
                revealAssetsInFinder?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(revealAssetsInFinder == nil)
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
