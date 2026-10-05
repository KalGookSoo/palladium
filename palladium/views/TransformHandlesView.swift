import SwiftUI

/// 미리보기 위에 고른 클립의 테두리와 크기 손잡이를 그린다. 테두리 안을 끌면 옮기고, 오른쪽 아래 손잡이를 끌면 크기를 바꾼다.
/// 끄는 동안에는 테두리만 따라 움직이고, 손을 떼면 한 번에 반영한다(영상은 다시 합성된 뒤 바뀐다).
struct TransformHandlesView: View {
    let transform: ClipTransform
    /// 클립 원본이 화면에 보이는 크기(회전 반영). 아직 모르면 테두리를 그리지 않는다.
    let contentSize: CGSize
    /// 합성 화면 크기(화면비 프리셋).
    let renderSize: CGSize
    let setTransform: (ClipTransform) -> Void
    @State private var draft: ClipTransform?

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
            let current = draft ?? transform
            let frame = current.frame(contentSize: contentSize, in: renderSize)
            let shownFrame = CGRect(
                x: shownRender.minX + frame.minX * fitScale,
                y: shownRender.minY + frame.minY * fitScale,
                width: frame.width * fitScale,
                height: frame.height * fitScale
            )

            ZStack(alignment: .topLeading) {
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
                    .gesture(resizeGesture(shownFrame: shownFrame))
            }
        }
        .help("끌어서 옮기고, 오른쪽 아래 손잡이로 크기를 바꿉니다")
    }

    private func moveGesture(shownRender: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var moved = transform
                moved.centerX += value.translation.width / shownRender.width
                moved.centerY += value.translation.height / shownRender.height
                draft = moved
            }
            .onEnded { _ in commitDraft() }
    }

    /// 오른쪽 아래 손잡이를 끈 만큼 폭을 바꾸고, 같은 비율로 배율을 바꾼다(가운데 기준).
    private func resizeGesture(shownFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard shownFrame.width > 0 else { return }
                var resized = transform
                let newWidth = max(shownFrame.width + value.translation.width * 2, 8)
                resized.scale = transform.scale * newWidth / shownFrame.width
                resized.clamp()
                draft = resized
            }
            .onEnded { _ in commitDraft() }
    }

    private func commitDraft() {
        if let draft {
            setTransform(draft)
        }
        draft = nil
    }
}
