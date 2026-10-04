import SwiftUI

/// 도움말 > 단축키 목록(⌘/)에서 여는 창.
struct ShortcutGuideView: View {
    var body: some View {
        List {
            ForEach(ShortcutGuide.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        LabeledContent {
                            Text(entry.keys ?? "")
                                .monospaced()
                        } label: {
                            Text(entry.title)
                            Text(entry.summary)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 520)
    }
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(ShortcutGuide.showShortcuts.title) {
                openWindow(id: SceneID.shortcutGuide)
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}

#Preview {
    ShortcutGuideView()
}
