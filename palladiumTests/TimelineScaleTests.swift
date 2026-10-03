import CoreMedia
@testable import palladium
import Testing

struct TimelineScaleTests {
    private let scale = TimelineScale(pointsPerSecond: 40)

    @Test("시각은 초당 포인트 배율만큼 가로 좌표로 바뀐다")
    func timeConvertsToX() {
        #expect(scale.x(for: seconds(2.5)) == 100)
        #expect(scale.width(for: seconds(10)) == 400)
    }

    @Test("가로 좌표를 시각으로 되돌리면 원래 시각이 된다")
    func xConvertsBackToTime() {
        #expect(scale.time(forX: 100) == seconds(2.5))
    }

    @Test("음수 좌표는 0초로 본다")
    func negativeXIsZero() {
        #expect(scale.time(forX: -30) == .zero)
    }

    @Test("줌 인·아웃은 배율을 두 배씩 바꾼다")
    func zoomStepsDoubleAndHalve() {
        #expect(scale.zoomedIn.pointsPerSecond == 80)
        #expect(scale.zoomedOut.pointsPerSecond == 20)
    }

    @Test("배율은 허용 범위를 넘지 않고, 끝에 닿으면 더 줌할 수 없다")
    func zoomIsClampedAtLimits() {
        let maximum = TimelineScale(pointsPerSecond: 10000)
        let minimum = TimelineScale(pointsPerSecond: 0.1)
        #expect(maximum.pointsPerSecond == TimelineScale.maximumPointsPerSecond)
        #expect(!maximum.canZoomIn)
        #expect(minimum.pointsPerSecond == TimelineScale.minimumPointsPerSecond)
        #expect(!minimum.canZoomOut)
    }

    @Test("핀치 배율을 곱한 새 배율을 만든다")
    func pinchMultipliesScale() {
        #expect(scale.zoomed(byMagnification: 1.5).pointsPerSecond == 60)
    }

    @Test("눈금 간격은 최소 60포인트가 되는 가장 작은 단위를 고른다")
    func labelIntervalKeepsLabelsApart() {
        #expect(TimelineScale(pointsPerSecond: 80).labelIntervalSeconds == 1)
        #expect(TimelineScale(pointsPerSecond: 40).labelIntervalSeconds == 2)
        #expect(TimelineScale(pointsPerSecond: 5).labelIntervalSeconds == 15)
    }
}

// MARK: - Helpers

private func seconds(_ value: Double) -> CMTime {
    CMTime(seconds: value, preferredTimescale: standardTimescale)
}
