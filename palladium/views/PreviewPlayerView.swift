import SwiftUI

struct PreviewPlayerView: View {
    var body: some View {
        ContentUnavailableView("미리보기 플레이어", systemImage: "play.rectangle")
    }
}

#Preview {
    PreviewPlayerView()
}
