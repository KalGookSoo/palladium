import SwiftUI

/// 미리보기 위에 고른 자막의 상자를 그린다(#82). 안을 끌면 자막이 따라 움직이고, 화면 가로·세로 가운데 근처에서는 자석처럼 붙는다.
/// 끄는 동안에는 테두리만 따라 움직이고, 손을 떼면 실제로 그려질 자리(가장자리 여백에 맞춘 상자)의 가운데로 한 번에 반영한다.
struct SubtitleHandlesView: View {
    let subtitle: Subtitle
    /// 합성 화면 크기(화면비 프리셋).
    let renderSize: CGSize
    let setPosition: (Double, Double) -> Void
    /// 끄는 중인 자막 가운데(화면 비율).
    @State private var draft: CGPoint?
    /// 끄는 동안 가로·세로 가운데 선에 붙었는지. 붙은 선을 진하게 보여준다.
    @State private var snapped = (x: false, y: false)
    /// 가운데 선에 붙는 거리(미리보기 포인트).
    private static let snapDistance = 8.0

    var body: some View {
        GeometryReader { geometry in
            // 플레이어는 합성 화면을 비율을 지켜 가운데 맞춰 보여준다.
            let fitScale = min(geometry.size.width / renderSize.width, geometry.size.height / renderSize.height)
            let shownRender = CGRect(
                x: (geometry.size.width - renderSize.width * fitScale) / 2,
                y: (geometry.size.height - renderSize.height * fitScale) / 2,
                width: renderSize.width * fitScale,
                height: renderSize.height * fitScale
            )
            // 자막을 고르면 안전 영역(상자가 갈 수 있는 끝)·3분할 격자·가운데 선을 옅게, 끄는 동안 진하게 보여준다.
            PositionGuides(
                render: shownRender,
                safeArea: SubtitleStyle.safeArea(in: renderSize),
                scale: fitScale,
                isDragging: draft != nil,
                snapped: snapped
            )
            .allowsHitTesting(false)
            if let frame = boxFrame(center: draft) {
                let shown = CGRect(
                    x: shownRender.minX + frame.minX * fitScale,
                    y: shownRender.minY + frame.minY * fitScale,
                    width: frame.width * fitScale,
                    height: frame.height * fitScale
                )
                Rectangle()
                    .strokeBorder(Color.teal, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .contentShape(Rectangle())
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
                    .gesture(moveGesture(start: shownCenter, shownRender: shownRender))
            }
        }
        .help("자막 — 끌어서 옮깁니다. 자막을 고른 채 방향키로도 옮깁니다(⇧는 크게)")
    }

    /// 실제로 그려지는 상자 가운데(화면 비율).
    private var shownCenter: CGPoint {
        boxFrame(center: nil).map { CGPoint(x: $0.midX / renderSize.width, y: $0.midY / renderSize.height) }
            ?? CGPoint(x: subtitle.style.centerX, y: subtitle.style.centerY)
    }

    /// `center`(화면 비율)에 둔 자막 상자(합성 화면 좌표, 왼쪽 위 원점). `nil`이면 지금 위치.
    private func boxFrame(center: CGPoint?) -> CGRect? {
        var placed = subtitle
        if let center {
            placed.style.centerX = center.x
            placed.style.centerY = center.y
            placed.style.clamp()
        }
        return SubtitleRenderer.frame(for: placed, renderSize: renderSize)
    }

    private func moveGesture(start: CGPoint, shownRender: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var x = start.x + value.translation.width / shownRender.width
                var y = start.y + value.translation.height / shownRender.height
                // 화면 가로·세로 가운데 근처면 가운데에 붙인다.
                let snapsX = abs(x - 0.5) * shownRender.width < Self.snapDistance
                let snapsY = abs(y - 0.5) * shownRender.height < Self.snapDistance
                if snapsX {
                    x = 0.5
                }
                if snapsY {
                    y = 0.5
                }
                snapped = (snapsX, snapsY)
                draft = CGPoint(x: x, y: y)
            }
            .onEnded { _ in
                // 여백에 맞춰 실제로 그려질 자리를 저장해, 다음 끌기·방향키가 보이는 자리에서 시작하게 한다.
                if let frame = boxFrame(center: draft) {
                    setPosition(frame.midX / renderSize.width, frame.midY / renderSize.height)
                }
                draft = nil
                snapped = (false, false)
            }
    }
}
