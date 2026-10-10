import CoreMedia
import Foundation

/// 클립 편집 창 필름스트립 막대의 배율(#97). 1이면 원본 전체가 보이는 폭에 맞는다(전체 맞춤).
/// 원본 길이(`duration`)와 막대가 보이는 폭(`visibleWidth`)을 받아 시간 ↔ 막대 안 가로 좌표를 바꾼다.
/// 보는 배율만 바꾸고 편집 기록에는 남지 않는다.
nonisolated struct TrimBarZoom {
    static let stepFactor = 2.0
    /// 가장 크게 확대했을 때 초당 포인트. 30fps면 한 프레임이 20pt쯤이다.
    static let maximumPointsPerSecond = 600.0
    /// ⌥를 누르고 끌 때 이동량 비율. 타임라인 정밀 트림과 같다.
    static let precisionFactor = 0.2

    /// 전체 맞춤 대비 배율. 1 이상이다.
    private(set) var magnification = 1.0
}

// MARK: - Queries

nonisolated extension TrimBarZoom {
    var isFit: Bool {
        magnification <= 1
    }

    /// 이 원본을 이 폭에서 볼 때 가장 큰 배율. 짧은 원본은 전체 맞춤이 이미 최대일 수 있다.
    static func maximumMagnification(duration: CMTime, visibleWidth: Double) -> Double {
        guard duration.seconds > 0, visibleWidth > 0 else { return 1 }
        return max(1, maximumPointsPerSecond * duration.seconds / visibleWidth)
    }

    func canZoomIn(duration: CMTime, visibleWidth: Double) -> Bool {
        magnification < Self.maximumMagnification(duration: duration, visibleWidth: visibleWidth)
    }

    var canZoomOut: Bool {
        !isFit
    }

    /// 막대 전체(스크롤되는 내용)의 폭.
    func contentWidth(visibleWidth: Double) -> Double {
        max(visibleWidth, 0) * magnification
    }

    func pointsPerSecond(duration: CMTime, visibleWidth: Double) -> Double {
        guard duration.seconds > 0 else { return 0 }
        return contentWidth(visibleWidth: visibleWidth) / duration.seconds
    }

    func x(for time: CMTime, duration: CMTime, visibleWidth: Double) -> Double {
        time.seconds * pointsPerSecond(duration: duration, visibleWidth: visibleWidth)
    }

    /// 막대 안 좌표의 시각. 원본 범위(0~길이) 안으로 맞춘다.
    func time(forX x: Double, duration: CMTime, visibleWidth: Double) -> CMTime {
        let pointsPerSecond = pointsPerSecond(duration: duration, visibleWidth: visibleWidth)
        guard pointsPerSecond > 0 else { return .zero }
        let seconds = min(max(x / pointsPerSecond, 0), duration.seconds)
        return CMTime(seconds: seconds, preferredTimescale: standardTimescale)
    }

    /// `factor`배 한 배율. 1(전체 맞춤)과 이 원본의 최대 배율 사이로 맞춘다.
    func zoomed(by factor: Double, duration: CMTime, visibleWidth: Double) -> TrimBarZoom {
        let maximum = Self.maximumMagnification(duration: duration, visibleWidth: visibleWidth)
        return TrimBarZoom(magnification: min(max(magnification * factor, 1), maximum))
    }

    /// `time`이 보이는 폭 안 `viewX`에 오도록 하는 스크롤 위치. 막대 밖으로 스크롤되지 않게 맞춘다.
    func scrollOffset(keeping time: CMTime, atViewX viewX: Double, duration: CMTime, visibleWidth: Double) -> Double {
        let maximumOffset = max(contentWidth(visibleWidth: visibleWidth) - visibleWidth, 0)
        let offset = x(for: time, duration: duration, visibleWidth: visibleWidth) - viewX
        return min(max(offset, 0), maximumOffset)
    }

    /// 끄는 동안 직전 위치(`previousX`, 그때 시각 `previousTime`)에서 `x`로 움직였을 때의 시각.
    /// ⌥(`isPrecise`)를 누르고 있으면 움직인 거리의 5분의 1만 옮기고, 아니면 포인터 아래 시각이다.
    func draggedTime(
        to x: Double,
        from previousX: Double,
        previousTime: CMTime,
        isPrecise: Bool,
        duration: CMTime,
        visibleWidth: Double
    ) -> CMTime {
        guard isPrecise else { return time(forX: x, duration: duration, visibleWidth: visibleWidth) }
        let pointsPerSecond = pointsPerSecond(duration: duration, visibleWidth: visibleWidth)
        guard pointsPerSecond > 0 else { return previousTime }
        let seconds = previousTime.seconds + (x - previousX) * Self.precisionFactor / pointsPerSecond
        return CMTime(seconds: min(max(seconds, 0), duration.seconds), preferredTimescale: standardTimescale)
    }
}

nonisolated extension TrimBarZoom: Equatable {}
