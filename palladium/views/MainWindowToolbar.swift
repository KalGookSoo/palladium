import SwiftUI

/// 같은 위치에 이어진 툴바 항목은 시스템이 한 캡슐로 묶어 그리므로, 항목마다 `ToolbarSpacer`를 두어 개별 버튼으로 분리한다.
struct MainWindowToolbar: ToolbarContent {
    @Binding var aspectRatio: AspectRatioPreset
    @Binding var isTimelineVisible: Bool
    @Binding var isInspectorPresented: Bool
    let hasUnsavedChanges: Bool
    let saveProject: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: saveProject) {
                Label("저장", systemImage: "checkmark")
            }
            .disabled(!hasUnsavedChanges)
            .help(hasUnsavedChanges ? "저장 (⌘S)" : "저장할 변경 사항 없음")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .navigation) {
            Button(action: requestMediaImport) {
                Label("가져오기", systemImage: "square.and.arrow.down")
            }
            .help("미디어 가져오기 (⌘I)")
        }

        ToolbarSpacer(.fixed, placement: .navigation)

        ToolbarItem(placement: .navigation) {
            Picker("화면비", selection: $aspectRatio) {
                ForEach(AspectRatioPreset.allCases) { preset in
                    Text("\(preset.widthRatio):\(preset.heightRatio)").tag(preset)
                }
            }
            .help("화면비 프리셋")
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: requestExport) {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .help("내보내기 (⌘E)")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                isTimelineVisible.toggle()
            } label: {
                Label("타임라인", systemImage: "rectangle.bottomhalf.inset.filled")
            }
            .help("타임라인 보기/가리기 (⌥⌘2)")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("인스펙터", systemImage: "sidebar.trailing")
            }
            .help("인스펙터 보기/가리기 (⌥⌘I)")
        }
    }
}
