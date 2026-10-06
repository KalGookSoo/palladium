import CoreMedia
import SwiftUI

/// 눈금은 길이에 따라 개수가 크게 달라져 표준 컨테이너로 그리기 어려우므로 `Canvas`로 그린다.
/// 위 줄에는 시간 글자, 아래 줄에는 눈금·마커·재생 헤드 머리를 두어 서로 겹치지 않게 한다(#79).
/// 눈금자를 누르거나 끌면 재생 헤드가 그 시각으로 가고, 재생 헤드 머리는 잡는 손잡이다.
struct TimelineRulerView: View {
    let scale: TimelineScale
    let sequenceDuration: CMTime
    let markers: [Marker]
    @Binding var playheadTime: CMTime
    var renameMarker: (Marker) -> Void = { _ in }
    var deleteMarker: (Marker.ID) -> Void = { _ in }
    /// 눈금자 위 마우스 위치. 그 시각을 툴팁처럼 보여준다.
    @State private var hoverX: Double?
    @State private var isScrubbing = false
    /// 재생 헤드 근처 이 거리 안의 시간 글자는 흐리게 그린다.
    private static let labelFadeDistance = 30.0
    /// 위 줄(시간 글자) 높이.
    private static let labelRowHeight = 13.0

    var body: some View {
        let playheadX = scale.x(for: playheadTime)

        Canvas { context, size in
            let interval = scale.labelIntervalSeconds
            let format = Duration.TimeFormatStyle(pattern: .minuteSecond)
            var second = 0.0
            while second * scale.pointsPerSecond <= size.width {
                let x = second * scale.pointsPerSecond
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: Self.labelRowHeight + 3))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .style(.secondary))

                let label = Text(Duration.seconds(second).formatted(format))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // 재생 헤드 가까이의 글자는 흐리게 해 머리·배지와 겹쳐 보이지 않게 한다.
                let isNearPlayhead = abs(x + 12 - playheadX) < Self.labelFadeDistance
                context.opacity = isNearPlayhead ? 0.25 : 1
                context.draw(label, at: CGPoint(x: x + 3, y: 0), anchor: .topLeading)
                context.opacity = 1
                second += interval
            }
        }
        .frame(height: TimelineMetrics.rulerHeight)
        .overlay(alignment: .topLeading) {
            ForEach(markers) { marker in
                MarkerView(
                    name: marker.name,
                    select: { playheadTime = marker.time },
                    rename: { renameMarker(marker) },
                    delete: { deleteMarker(marker.id) }
                )
                .offset(x: scale.x(for: marker.time) - 5, y: TimelineMetrics.rulerHeight - 14)
            }
        }
        .overlay(alignment: .topLeading) {
            playheadHandle
                .offset(x: playheadX - PlayheadHandle.width / 2, y: TimelineMetrics.rulerHeight - PlayheadHandle.height)
        }
        .overlay(alignment: .topLeading) { timeBadge(playheadX: playheadX) }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location): hoverX = location.x
            case .ended: hoverX = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isScrubbing = true
                    playheadTime = CMTimeMinimum(scale.time(forX: value.location.x), sequenceDuration)
                }
                .onEnded { _ in isScrubbing = false }
        )
        .accessibilityLabel("눈금자")
        .accessibilityHint("클릭하거나 끌어서 재생 헤드를 옮깁니다")
    }

    /// 눈금자 아래 줄의 재생 헤드 머리. 마우스를 올리면 좌우 이동 커서가 되고, 끌면 눈금자 끌기와 같이 재생 헤드가 따라온다.
    private var playheadHandle: some View {
        PlayheadHandle()
            .pointerStyle(.columnResize)
            .help("재생 헤드 — 끌어서 옮깁니다")
    }

    /// 끄는 동안에는 재생 헤드 시각을, 아니면 마우스 위치 시각을 위 줄에 배지로 보여준다(툴팁 대신 마우스를 따라 바뀐다).
    @ViewBuilder
    private func timeBadge(playheadX: Double) -> some View {
        if let badgeX = isScrubbing ? playheadX : hoverX {
            let time = isScrubbing ? playheadTime : CMTimeMinimum(scale.time(forX: badgeX), sequenceDuration)
            Text(scale.timeLabel(for: time))
                .font(.caption2)
                .monospacedDigit()
                .padding(.horizontal, 4)
                .background(isScrubbing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Capsule())
                .foregroundStyle(isScrubbing ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .fixedSize()
                .offset(x: max(badgeX + 4, 0), y: -1)
                .allowsHitTesting(false)
        }
    }
}

/// 재생 헤드 머리(아래를 가리키는 삼각형). 세로선은 `PlayheadView`가 그린다.
private struct PlayheadHandle: View {
    static let width = 12.0
    static let height = 12.0

    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .resizable()
            .foregroundStyle(Color.accentColor)
            .frame(width: Self.width, height: Self.height)
            .contentShape(Rectangle())
            .accessibilityLabel("재생 헤드")
    }
}
