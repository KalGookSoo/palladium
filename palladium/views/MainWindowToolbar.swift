import SwiftUI

/// 같은 위치에 이어진 툴바 항목은 시스템이 한 캡슐로 묶어 그리므로, 항목마다 `ToolbarSpacer`를 두어 개별 버튼으로 분리한다.
struct MainWindowToolbar: ToolbarContent {
    @Binding var aspectRatio: AspectRatioPreset
    @Binding var isInspectorPresented: Bool
    let importMedia: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: importMedia) {
                Label("가져오기", systemImage: "square.and.arrow.down")
            }
            .help(ShortcutGuide.importMedia.helpText)
        }

        ToolbarSpacer(.fixed, placement: .navigation)

        ToolbarItem(placement: .navigation) {
            Picker("화면비", selection: $aspectRatio) {
                ForEach(AspectRatioPreset.allCases) { preset in
                    Text("\(preset.widthRatio):\(preset.heightRatio)").tag(preset)
                }
            }
            .help(ShortcutGuide.aspectRatio.helpText)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: requestExport) {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .help(ShortcutGuide.export.helpText)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("인스펙터", systemImage: "sidebar.trailing")
            }
            .help(ShortcutGuide.toggleInspector.helpText)
        }
    }
}
