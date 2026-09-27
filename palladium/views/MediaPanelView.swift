import SwiftUI

struct MediaPanelView: View {
    var body: some View {
        ContentUnavailableView("미디어 패널", systemImage: "photo.on.rectangle.angled")
    }
}

#Preview {
    MediaPanelView()
}
