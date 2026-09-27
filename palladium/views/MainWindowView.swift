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
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                if isTimelineVisible {
                    TimelineEditorView()
                        .frame(maxWidth: .infinity, minHeight: 160, idealHeight: 240, maxHeight: .infinity)
                }
            }
            // 창이 좁아질 때 양쪽 패널 대신 가운데가 먼저 줄어들도록 최소 폭을 명시한다.
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
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
