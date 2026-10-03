import SwiftUI

/// 트랙 종류는 색이 아니라 트랙 레이블과 클립 내용 모양으로 구분하므로 바탕은 중립색으로 둔다.
/// 영상 필름스트립·오디오 파형이 생기기 전까지는 종류 아이콘이 그 자리를 대신한다.
struct ClipView: View {
    let title: String
    let symbolName: String
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(isSelected ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
            .overlay {
                Rectangle()
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .overlay(alignment: .leading) {
                Label(title, systemImage: symbolName)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack {
        ClipView(title: "intro.mov", symbolName: "film", isSelected: false)
        ClipView(title: "b-roll.mov", symbolName: "film", isSelected: true)
        ClipView(title: "background-music.m4a", symbolName: "waveform", isSelected: false)
    }
    .frame(width: 200, height: 120)
    .padding()
}
