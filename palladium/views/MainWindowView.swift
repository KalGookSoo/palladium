import SwiftUI

struct MainWindowView: View {
    @State private var isTimelineVisible = true
    @State private var isInspectorPresented = true

    var body: some View {
        NavigationSplitView {
            MediaPanelView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VSplitView {
                PreviewPlayerView()
                    .frame(minHeight: 240)
                if isTimelineVisible {
                    TimelineEditorView()
                        .frame(minHeight: 160, idealHeight: 240)
                }
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isTimelineVisible.toggle()
                } label: {
                    Label("타임라인", systemImage: "rectangle.bottomhalf.inset.filled")
                }
                .help("타임라인 보기/가리기 (⌥⌘2)")

                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("인스펙터", systemImage: "sidebar.trailing")
                }
                .help("인스펙터 보기/가리기 (⌥⌘I)")
            }
        }
        .focusedSceneValue(\.isTimelineVisible, $isTimelineVisible)
        .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    MainWindowView()
}
