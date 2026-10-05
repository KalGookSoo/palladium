import SwiftUI

/// 누르면 재생 헤드를 마커로 옮기고, 우클릭으로 이름을 바꾸거나 지운다.
struct MarkerView: View {
    let name: String
    var select: () -> Void = {}
    var rename: () -> Void = {}
    var delete: () -> Void = {}

    var body: some View {
        // 재생 헤드(강조색)와 구분되어야 하므로 시스템 주황색을 쓴다.
        Image(systemName: "bookmark.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .contextMenu {
                Button("마커 이름 변경…", action: rename)
                Button("마커 삭제", action: delete)
            }
            .help("\(name) — 누르면 재생 헤드가 이 마커로 갑니다")
            .accessibilityLabel("마커: \(name)")
    }
}

#Preview {
    MarkerView(name: "인트로 끝")
        .padding()
}
