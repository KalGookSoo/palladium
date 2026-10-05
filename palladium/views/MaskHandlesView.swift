import SwiftUI

/// 미리보기 위에 고른 마스크의 영역을 그린다. 안을 끌면 옮기고, 오른쪽 아래 손잡이를 끌면 너비·높이를 따로 바꾼다(가운데 기준).
/// 끄는 동안에는 테두리만 따라 움직이고, 손을 떼면 한 번에 반영한다.
struct MaskHandlesView: View {
    let mask: Mask
    /// 합성 화면 크기(화면비 프리셋).
    let renderSize: CGSize
    let setArea: (MaskArea) -> Void
    @State private var draft: MaskArea?

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
            let area = (draft ?? mask.area).rect(in: shownRender.size)
            let shownFrame = area.offsetBy(dx: shownRender.minX, dy: shownRender.minY)

            ZStack(alignment: .topLeading) {
                Group {
                    if mask.shape == .ellipse {
                        Ellipse().strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    } else {
                        Rectangle().strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
                .contentShape(Rectangle())
                .frame(width: shownFrame.width, height: shownFrame.height)
                .offset(x: shownFrame.minX, y: shownFrame.minY)
                .gesture(moveGesture(shownRender: shownRender))
                Circle()
                    .fill(Color.purple)
                    .frame(width: 12, height: 12)
                    .offset(x: shownFrame.maxX - 6, y: shownFrame.maxY - 6)
                    .pointerStyle(.frameResize(position: .bottomTrailing))
                    .gesture(resizeGesture(shownRender: shownRender))
            }
        }
        .help("마스크 — 끌어서 옮기고, 오른쪽 아래 손잡이로 크기를 바꿉니다")
    }

    private func moveGesture(shownRender: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var moved = mask.area
                moved.centerX += value.translation.width / shownRender.width
                moved.centerY += value.translation.height / shownRender.height
                moved.clamp()
                draft = moved
            }
            .onEnded { _ in commitDraft() }
    }

    private func resizeGesture(shownRender: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var resized = mask.area
                resized.width += value.translation.width * 2 / shownRender.width
                resized.height += value.translation.height * 2 / shownRender.height
                resized.clamp()
                draft = resized
            }
            .onEnded { _ in commitDraft() }
    }

    private func commitDraft() {
        if let draft {
            setArea(draft)
        }
        draft = nil
    }
}
