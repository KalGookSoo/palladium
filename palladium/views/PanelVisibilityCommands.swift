import SwiftUI

extension FocusedValues {
    @Entry var isTimelineVisible: Binding<Bool>?
    @Entry var isInspectorPresented: Binding<Bool>?
}

struct PanelVisibilityCommands: Commands {
    @AppStorage(AppPreferences.timelineShowsFilmstripKey) private var showsFilmstrip = true
    @AppStorage(AppPreferences.timelineShowsWaveformKey) private var showsWaveform = true
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

            Divider()
            // 타임라인 클립 안에 그릴 내용. 타임라인 머리의 "클립 보기" 메뉴와 같은 설정이다.
            Toggle(ShortcutGuide.toggleFilmstrip.title, isOn: $showsFilmstrip)
            Toggle(ShortcutGuide.toggleWaveform.title, isOn: $showsWaveform)
        }
    }
}
