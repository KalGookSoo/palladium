import SwiftUI

/// 미리보기 위에 고른 클립의 테두리와 크기 손잡이를 그린다. 테두리 안을 끌면 옮기고, 오른쪽 아래 손잡이를 끌면 크기를 바꾼다.
/// 끄는 동안에는 테두리만 따라 움직이고, 손을 떼면 한 번에 반영한다(영상은 다시 합성된 뒤 바뀐다).
/// 끄는 거리는 창 좌표로 재고 늘 끌기 시작 때의 트랜스폼(`transform`)을 기준으로 계산해, 옮겨 그려진 테두리가 계산에 되먹임되지 않게 한다(#84).
struct TransformHandlesView: View {
    let transform: ClipTransform
    /// 클립 원본이 화면에 보이는 크기(회전 반영). 아직 모르면 테두리를 그리지 않는다.
    let contentSize: CGSize
    /// 합성 화면 크기(화면비 프리셋).
    let renderSize: CGSize
    let setTransform: (ClipTransform) -> Void
    @State private var draft: ClipTransform?
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
            let shownFrame = shown(draft ?? transform, in: shownRender, scale: fitScale)
            // 크기 계산의 기준: 끌기 시작 때(반영된 트랜스폼)의 테두리 폭.
            let startWidth = shown(transform, in: shownRender, scale: fitScale).width

            ZStack(alignment: .topLeading) {
                // 끄는 동안 3분할 격자와 화면 가운데 선을 보여준다.
                if draft != nil {
                    PositionGuides(render: shownRender, scale: fitScale, isDragging: true, snapped: snapped)
                        .allowsHitTesting(false)
                }
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .contentShape(Rectangle())
                    .frame(width: shownFrame.width, height: shownFrame.height)
                    .offset(x: shownFrame.minX, y: shownFrame.minY)
                    .gesture(moveGesture(shownRender: shownRender))
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(x: shownFrame.maxX - 6, y: shownFrame.maxY - 6)
                    .pointerStyle(.frameResize(position: .bottomTrailing))
                    .gesture(resizeGesture(startWidth: startWidth))
            }
        }
        .help("끌어서 옮기고, 오른쪽 아래 손잡이로 크기를 바꿉니다")
    }

    /// 트랜스폼 테두리가 미리보기에 그려지는 사각형.
    private func shown(_ transform: ClipTransform, in shownRender: CGRect, scale: Double) -> CGRect {
        let frame = transform.frame(contentSize: contentSize, in: renderSize)
        return CGRect(
            x: shownRender.minX + frame.minX * scale,
            y: shownRender.minY + frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    /// 테두리 안을 끈 만큼 옮긴다. 화면 가로·세로 가운데 근처면 가운데에 붙는다.
    private func moveGesture(shownRender: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                guard shownRender.width > 0, shownRender.height > 0 else { return }
                let result = transform.moved(
                    by: CGVector(
                        dx: value.translation.width / shownRender.width,
                        dy: value.translation.height / shownRender.height
                    ),
                    snap: CGVector(dx: Self.snapDistance / shownRender.width, dy: Self.snapDistance / shownRender.height)
                )
                snapped = result.snapped
                draft = result.transform
            }
            .onEnded { _ in commitDraft() }
    }

    /// 오른쪽 아래 손잡이를 끈 만큼 폭을 바꾸고, 같은 비율로 배율을 바꾼다(가운데 기준).
    private func resizeGesture(startWidth: Double) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                draft = transform.resized(widthChange: value.translation.width * 2, startWidth: startWidth)
            }
            .onEnded { _ in commitDraft() }
    }

    private func commitDraft() {
        if let draft {
            setTransform(draft)
        }
        draft = nil
        snapped = (false, false)
    }
}
