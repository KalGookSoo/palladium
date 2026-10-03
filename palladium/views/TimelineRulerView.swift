import CoreMedia
import SwiftUI

/// 눈금은 길이에 따라 개수가 크게 달라져 표준 컨테이너로 그리기 어려우므로 `Canvas`로 그린다.
struct TimelineRulerView: View {
    let scale: TimelineScale
    let sequenceDuration: CMTime
    let markers: [Marker]
    @Binding var playheadTime: CMTime

    var body: some View {
        Canvas { context, size in
            let interval = scale.labelIntervalSeconds
            let format = Duration.TimeFormatStyle(pattern: .minuteSecond)
            var second = 0.0
            while second * scale.pointsPerSecond <= size.width {
                let x = second * scale.pointsPerSecond
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height * 0.5))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .style(.secondary))

                let label = Text(Duration.seconds(second).formatted(format))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                context.draw(label, at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                second += interval
            }
        }
        .frame(height: TimelineMetrics.rulerHeight)
        .overlay(alignment: .topLeading) {
            ForEach(markers) { marker in
                MarkerView(name: marker.name)
                    .offset(x: scale.x(for: marker.time) - 5, y: TimelineMetrics.rulerHeight - 14)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                playheadTime = CMTimeMinimum(scale.time(forX: value.location.x), sequenceDuration)
            }
        )
        .accessibilityLabel("눈금자")
        .accessibilityHint("클릭하거나 끌어서 재생 헤드를 옮깁니다")
    }
}
