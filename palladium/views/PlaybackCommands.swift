import SwiftUI

extension FocusedValues {
    /// 편집 창이 앞에 있을 때만 값이 있다. 재생·타임라인 메뉴의 한 글자 단축키 항목이 키를 누른 것과 같은 일을 하게 한다(#64).
    @Entry var editorCommand: ((EditorKeyMonitor.Key) -> Void)?
    /// 편집 창이 앞에 있을 때만 값이 있다(#64, ⌘N).
    @Entry var newSequence: (() -> Void)?
    /// 앞·뒤에 시퀀스가 있을 때만 값이 있다(#64, ⌘[ / ⌘]).
    @Entry var previousSequence: (() -> Void)?
    @Entry var nextSequence: (() -> Void)?
    /// 기본 전환을 넣을 클립이 있을 때만 값이 있다(#64, ⇧⌘T).
    @Entry var addDefaultTransition: (() -> Void)?
}

/// 재생 메뉴와 타임라인 메뉴(#64). 한 글자 단축키(Space·J/K/L·M·T·R·방향키 등)는 입력란 글자를 가로채지 않도록
/// 메뉴 단축키로 두지 않고 `EditorKeyMonitor`가 받는다. 메뉴에는 이름 뒤에 키를 적어 찾을 수 있게만 한다.
struct PlaybackCommands: Commands {
    @FocusedValue(\.editorCommand) private var editorCommand
    @FocusedValue(\.previousSequence) private var previousSequence
    @FocusedValue(\.nextSequence) private var nextSequence
    @FocusedValue(\.addDefaultTransition) private var addDefaultTransition

    var body: some Commands {
        CommandMenu("재생") {
            item(ShortcutGuide.playPause, .playPause)
            item(ShortcutGuide.shuttleReverse, .shuttleReverse)
            item(ShortcutGuide.shuttleStop, .shuttleStop)
            item(ShortcutGuide.shuttleForward, .shuttleForward)
            Divider()
            item(ShortcutGuide.goToStart, .goToStart)
            item(ShortcutGuide.goToEnd, .goToEnd)
            item(ShortcutGuide.previousEditPoint, .moveUp)
            item(ShortcutGuide.nextEditPoint, .moveDown)
            item(ShortcutGuide.previousFrame, .previousFrame)
            item(ShortcutGuide.nextFrame, .nextFrame)
            item(ShortcutGuide.tenFramesBack, .moveLeftLarge)
            item(ShortcutGuide.tenFramesForward, .moveRightLarge)
            Divider()
            item(ShortcutGuide.narration, .toggleNarration)
        }

        CommandMenu("타임라인") {
            item(ShortcutGuide.addMarker, .addMarker)
            item(ShortcutGuide.addSubtitle, .addSubtitle)
            Button(ShortcutGuide.addDefaultTransition.title) {
                addDefaultTransition?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(addDefaultTransition == nil)
            Divider()
            item(ShortcutGuide.fitTimeline, .fitTimeline)
            Divider()
            Button(ShortcutGuide.previousSequence.title) {
                previousSequence?()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(previousSequence == nil)
            Button(ShortcutGuide.nextSequence.title) {
                nextSequence?()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(nextSequence == nil)
        }
    }

    /// 한 글자 단축키 항목. 이름 뒤에 키를 적고, 누르면 그 키를 누른 것과 같은 일을 한다.
    private func item(_ entry: ShortcutGuideEntry, _ key: EditorKeyMonitor.Key) -> some View {
        Button(entry.menuTitle) {
            editorCommand?(key)
        }
        .disabled(editorCommand == nil)
    }
}
