import SwiftUI

/// 미리보기에서 무언가를 옮길 때 보여주는 보조선(#82, #84). 사진 앱 격자처럼 3분할하고, 화면 가로·세로 가운데 선을 그린다.
/// 안전 영역이 있으면(자막) 그 안을 3분할하고 테두리를 점선으로, 없으면(클립) 화면 전체를 3분할한다.
struct PositionGuides: View {
    /// 미리보기 안에서 합성 화면이 보이는 사각형.
    let render: CGRect
    /// 합성 화면 좌표의 안전 영역. `nil`이면 화면 전체.
    var safeArea: CGRect?
    let scale: Double
    let isDragging: Bool
    let snapped: (x: Bool, y: Bool)

    var body: some View {
        let area = safeArea.map {
            CGRect(
                x: render.minX + $0.minX * scale,
                y: render.minY + $0.minY * scale,
                width: $0.width * scale,
                height: $0.height * scale
            )
        } ?? render
        let strength = isDragging ? 0.6 : 0.3
        ZStack(alignment: .topLeading) {
            // 3분할 격자.
            Path { path in
                for index in 1 ... 2 {
                    let x = area.minX + area.width * Double(index) / 3
                    let y = area.minY + area.height * Double(index) / 3
                    path.move(to: CGPoint(x: x, y: area.minY))
                    path.addLine(to: CGPoint(x: x, y: area.maxY))
                    path.move(to: CGPoint(x: area.minX, y: y))
                    path.addLine(to: CGPoint(x: area.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(strength * 0.5), lineWidth: 0.5)
            // 안전 영역 테두리: 자막 상자는 이 안에서만 움직인다.
            if safeArea != nil {
                Rectangle()
                    .stroke(Color.teal.opacity(strength), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .frame(width: area.width, height: area.height)
                    .offset(x: area.minX, y: area.minY)
            }
            // 가운데 선. 붙으면 진하게.
            Path { path in
                path.move(to: CGPoint(x: render.midX, y: area.minY))
                path.addLine(to: CGPoint(x: render.midX, y: area.maxY))
            }
            .stroke(Color.yellow.opacity(snapped.x ? 0.9 : strength * 0.6), lineWidth: snapped.x ? 1.5 : 0.5)
            Path { path in
                path.move(to: CGPoint(x: area.minX, y: render.midY))
                path.addLine(to: CGPoint(x: area.maxX, y: render.midY))
            }
            .stroke(Color.yellow.opacity(snapped.y ? 0.9 : strength * 0.6), lineWidth: snapped.y ? 1.5 : 0.5)
        }
    }
}
