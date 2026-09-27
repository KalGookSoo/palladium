import SwiftUI

extension FocusedValues {
    @Entry var isTimelineVisible: Binding<Bool>?
    @Entry var isInspectorPresented: Binding<Bool>?
}

struct PanelVisibilityCommands: Commands {
    @FocusedBinding(\.isTimelineVisible) private var isTimelineVisible
    @FocusedBinding(\.isInspectorPresented) private var isInspectorPresented

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(isTimelineVisible == true ? "타임라인 가리기" : "타임라인 보기") {
                isTimelineVisible?.toggle()
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(isTimelineVisible == nil)

            Button(isInspectorPresented == true ? "인스펙터 가리기" : "인스펙터 보기") {
                isInspectorPresented?.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(isInspectorPresented == nil)
        }
    }
}
