import SwiftUI

/// SwiftUI의 `TimelineView`(일정 주기로 다시 그리는 View)와 이름이 겹치지 않도록 `TimelineEditorView`로 짓는다.
struct TimelineEditorView: View {
    var body: some View {
        ContentUnavailableView("타임라인", systemImage: "film")
    }
}

#Preview {
    TimelineEditorView()
}
