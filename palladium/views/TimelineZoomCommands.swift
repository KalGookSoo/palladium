import SwiftUI

extension FocusedValues {
    @Entry var timelineScale: Binding<TimelineScale>?
    /// 타임라인이 아닌 확대 대상(클립 편집 창 필름스트립 막대, #97). 있으면 보기 메뉴가 이것을 확대·축소한다.
    @Entry var zoomCommand: ZoomCommand?
}

/// 앞에 있는 창의 확대·축소 동작(#97). 동작이 `nil`이면 그 메뉴 항목이 꺼진다.
struct ZoomCommand {
    /// 메뉴 이름 앞에 붙는 대상. 예: "필름스트립" → "필름스트립 확대".
    let target: String
    let zoomIn: (() -> Void)?
    let zoomOut: (() -> Void)?
    let fit: (() -> Void)?
}

struct TimelineZoomCommands: Commands {
    @FocusedBinding(\.timelineScale) private var timelineScale
    @FocusedValue(\.zoomCommand) private var zoomCommand

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            // 클립 편집 창이 앞에 있으면 그 창의 필름스트립 막대를 확대·축소한다(⌘S가 창마다 다른 #92와 같은 방식).
            if let zoomCommand {
                Button("\(zoomCommand.target) 확대") { zoomCommand.zoomIn?() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(zoomCommand.zoomIn == nil)

                Button("\(zoomCommand.target) 축소") { zoomCommand.zoomOut?() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(zoomCommand.zoomOut == nil)

                Button("\(zoomCommand.target) 전체 맞춤") { zoomCommand.fit?() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(zoomCommand.fit == nil)
            } else {
                Button("타임라인 확대") {
                    timelineScale = timelineScale?.zoomedIn
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(timelineScale?.canZoomIn != true)

                Button("타임라인 축소") {
                    timelineScale = timelineScale?.zoomedOut
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(timelineScale?.canZoomOut != true)
            }
        }
    }
}
