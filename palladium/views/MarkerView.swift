import SwiftUI

struct MarkerView: View {
    let name: String

    var body: some View {
        // 재생 헤드(강조색)와 구분되어야 하므로 시스템 주황색을 쓴다.
        Image(systemName: "bookmark.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .help(name)
            .accessibilityLabel("마커: \(name)")
    }
}

#Preview {
    MarkerView(name: "인트로 끝")
        .padding()
}
