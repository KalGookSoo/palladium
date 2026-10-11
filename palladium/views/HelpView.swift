import SwiftUI

/// 도움말 > palladium 도움말(⇧⌘/)·단축키 목록(⌘/)에서 여는 창. 기능 안내와 전체 단축키를 한곳에서 보고 검색한다.
struct HelpView: View {
    @State private var query = ""

    var body: some View {
        let search = HelpSearch(query: query)
        let topics = HelpContent.topics.filter(search.matches)
        let shortcutSections = ShortcutGuide.sections
            .map { (title: $0.title, entries: $0.entries.filter(search.matches)) }
            .filter { !$0.entries.isEmpty }

        List {
            if !topics.isEmpty {
                Section("기능 안내") {
                    ForEach(topics) { topic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.headline)
                            Text(topic.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            ForEach(shortcutSections, id: \.title) { section in
                Section("단축키 — \(section.title)") {
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
        .overlay {
            if topics.isEmpty, shortcutSections.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "도움말 검색")
        .frame(width: 520, height: 600)
    }
}

extension FocusedValues {
    /// 둘러보기 프로젝트에서 목록을 닫아 두었을 때만 값이 있다(#63).
    @Entry var showTourChecklist: (() -> Void)?
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.showTourChecklist) private var showTourChecklist

    var body: some Commands {
        // 시스템 기본 항목은 Help Book이 없어 "도움말을 사용할 수 없음"만 보여주므로 앱 내 도움말로 바꾼다.
        CommandGroup(replacing: .help) {
            Button("palladium 도움말") {
                openWindow(id: SceneID.help)
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            Button(ShortcutGuide.showShortcuts.title) {
                openWindow(id: SceneID.help)
            }
            .keyboardShortcut("/", modifiers: .command)
            Divider()
            // 시작 창을 열어 샘플 프로젝트를 만들고 연다(#63). 자동으로 열지는 않는다.
            Button("샘플 프로젝트로 둘러보기…") {
                LauncherRequests.shared.pending = .tour
                openWindow(id: SceneID.launcher)
            }
            Button("둘러보기 목록 보기") {
                showTourChecklist?()
            }
            .disabled(showTourChecklist == nil)
        }
    }
}

#Preview {
    HelpView()
}
