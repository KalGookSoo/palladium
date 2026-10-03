import SwiftUI

extension FocusedValues {
    @Entry var timelineScale: Binding<TimelineScale>?
}

struct TimelineZoomCommands: Commands {
    @FocusedBinding(\.timelineScale) private var timelineScale

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

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
