import CoreMedia
import Foundation
@testable import palladium
import Testing

/// 클립 편집 창 필름스트립 막대 확대·축소와 ⌥ 정밀 끌기(#97).
struct TrimBarZoomTests {
    private let duration = CMTime(value: 120, timescale: 1)
    private let width = 1200.0

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("전체 맞춤이면 원본 전체가 보이는 폭에 맞고, 확대하면 그만큼 막대가 넓어진다")
    func coordinates() {
        var zoom = TrimBarZoom()
        #expect(zoom.isFit)
        #expect(zoom.x(for: seconds(60), duration: duration, visibleWidth: width) == 600)
        #expect(zoom.time(forX: 300, duration: duration, visibleWidth: width) == seconds(30))

        zoom = zoom.zoomed(by: TrimBarZoom.stepFactor, duration: duration, visibleWidth: width)
        #expect(zoom.contentWidth(visibleWidth: width) == 2400)
        #expect(zoom.x(for: seconds(60), duration: duration, visibleWidth: width) == 1200)
        #expect(zoom.time(forX: 2400, duration: duration, visibleWidth: width) == seconds(120))
        // 막대 밖 좌표는 원본 범위 안으로 맞춘다.
        #expect(zoom.time(forX: -50, duration: duration, visibleWidth: width) == .zero)
        #expect(zoom.time(forX: 9999, duration: duration, visibleWidth: width) == duration)
    }

    @Test("배율은 전체 맞춤(1)보다 작아지지 않고, 초당 600pt를 넘지 않는다")
    func clampsMagnification() {
        let zoomedOut = TrimBarZoom().zoomed(by: 0.5, duration: duration, visibleWidth: width)
        #expect(zoomedOut.isFit)
        #expect(!zoomedOut.canZoomOut)

        var zoom = TrimBarZoom()
        for _ in 0 ..< 20 {
            zoom = zoom.zoomed(by: TrimBarZoom.stepFactor, duration: duration, visibleWidth: width)
        }
        #expect(zoom.pointsPerSecond(duration: duration, visibleWidth: width) == TrimBarZoom.maximumPointsPerSecond)
        #expect(!zoom.canZoomIn(duration: duration, visibleWidth: width))
        // 1초짜리 원본은 전체 맞춤(1200pt/초)이 이미 최대보다 넓어 확대할 수 없다.
        #expect(!TrimBarZoom().canZoomIn(duration: seconds(1), visibleWidth: width))
    }

    @Test("확대할 때 기준 시각(재생 위치)이 보이는 폭 안 같은 자리에 머물도록 스크롤 위치를 정하고, 막대 밖으로는 스크롤하지 않는다")
    func keepsAnchor() {
        let zoom = TrimBarZoom().zoomed(by: 4, duration: duration, visibleWidth: width)
        // 60초가 보이는 폭의 300pt 자리에 오도록.
        let offset = zoom.scrollOffset(keeping: seconds(60), atViewX: 300, duration: duration, visibleWidth: width)
        #expect(zoom.x(for: seconds(60), duration: duration, visibleWidth: width) - offset == 300)
        #expect(zoom.scrollOffset(keeping: seconds(1), atViewX: 600, duration: duration, visibleWidth: width) == 0)
        #expect(zoom.scrollOffset(keeping: seconds(119), atViewX: 0, duration: duration, visibleWidth: width) == 4800 - width)
    }

    @Test("⌥를 누르고 끌면 움직인 거리의 5분의 1만 옮기고, 아니면 포인터 아래 시각이다")
    func precisionDrag() {
        let zoom = TrimBarZoom()
        // 전체 맞춤에서 10pt = 1초. ⌥면 0.2초.
        let precise = zoom.draggedTime(to: 110, from: 100, previousTime: seconds(10), isPrecise: true, duration: duration, visibleWidth: width)
        #expect(abs(precise.seconds - 10.2) < 0.001)
        let normal = zoom.draggedTime(to: 110, from: 100, previousTime: seconds(10), isPrecise: false, duration: duration, visibleWidth: width)
        #expect(normal == seconds(11))
        let clamped = zoom.draggedTime(to: 0, from: 100, previousTime: seconds(1), isPrecise: true, duration: duration, visibleWidth: width)
        #expect(clamped == .zero)
    }
}
