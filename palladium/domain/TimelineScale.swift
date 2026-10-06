import CoreMedia
import Foundation

/// 타임라인의 시간 ↔ 가로 좌표 변환과 줌 단계. 좌표는 CoreGraphics에 의존하지 않도록 `Double`(포인트)로 다룬다.
nonisolated struct TimelineScale {
    static let minimumPointsPerSecond = 5.0
    static let maximumPointsPerSecond = 640.0
    static let zoomStepFactor = 2.0

    let pointsPerSecond: Double

    /// 허용 범위를 벗어난 배율은 가장 가까운 한계값으로 맞춘다.
    init(pointsPerSecond: Double) {
        self.pointsPerSecond = min(max(pointsPerSecond, Self.minimumPointsPerSecond), Self.maximumPointsPerSecond)
    }
}

// MARK: - Queries

nonisolated extension TimelineScale {
    func x(for time: CMTime) -> Double {
        time.seconds * pointsPerSecond
    }

    func width(for duration: CMTime) -> Double {
        x(for: duration)
    }

    /// 음수 좌표는 0초로 본다.
    func time(forX x: Double) -> CMTime {
        CMTime(seconds: max(x, 0) / pointsPerSecond, preferredTimescale: standardTimescale)
    }

    var zoomedIn: TimelineScale {
        TimelineScale(pointsPerSecond: pointsPerSecond * Self.zoomStepFactor)
    }

    var zoomedOut: TimelineScale {
        TimelineScale(pointsPerSecond: pointsPerSecond / Self.zoomStepFactor)
    }

    /// 핀치 제스처의 배율(1이면 그대로)을 곱한 새 배율.
    func zoomed(byMagnification magnification: Double) -> TimelineScale {
        TimelineScale(pointsPerSecond: pointsPerSecond * magnification)
    }

    var canZoomIn: Bool {
        pointsPerSecond < Self.maximumPointsPerSecond
    }

    var canZoomOut: Bool {
        pointsPerSecond > Self.minimumPointsPerSecond
    }

    /// 재생 헤드·커서 위치 시각(분:초.소수, #79). 확대했을 때(초당 100pt 이상)만 소수 둘째 자리까지 보인다.
    /// 반올림하면 59.99초가 1:00.0처럼 실제보다 늦게 보이므로 버린다.
    func timeLabel(for time: CMTime) -> String {
        let fractionDigits = pointsPerSecond >= 100 ? 2 : 1
        let unitsPerSecond = fractionDigits == 2 ? 100 : 10
        let totalUnits = Int((max(time.seconds, 0) * Double(unitsPerSecond) + 1e-6).rounded(.down))
        let fraction = totalUnits % unitsPerSecond
        let totalSeconds = totalUnits / unitsPerSecond
        let fractionText = String(fraction).leftPadded(to: fractionDigits)
        return "\(totalSeconds / 60):\(String(totalSeconds % 60).leftPadded(to: 2)).\(fractionText)"
    }

    /// 눈금 사이가 너무 좁아 글자가 겹치지 않도록, 눈금 간격이 최소 60포인트가 되는 가장 작은 단위(초)를 고른다.
    var labelIntervalSeconds: Double {
        let candidates = [1.0, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return candidates.first { $0 * pointsPerSecond >= 60 } ?? candidates[candidates.count - 1]
    }
}

nonisolated extension TimelineScale: Equatable {}

private nonisolated extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(length - count, 0)) + self
    }
}
