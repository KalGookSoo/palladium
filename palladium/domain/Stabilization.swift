import CoreMedia
import Foundation

/// 클립 손떨림 보정 설정(#71). 있으면 켜진 것이고, 원본 분석(`MotionPath`)이 끝나야 실제로 보정된다.
nonisolated struct ClipStabilization {
    /// 세기(0~1). 클수록 더 긴 시간에 걸쳐 흔들림을 고르게 펴고, 그만큼 화면을 더 확대한다.
    var strength = 0.5
}

nonisolated extension ClipStabilization: Equatable {}

nonisolated extension ClipStabilization {
    mutating func clamp() {
        strength = min(max(strength, 0), 1)
    }

    /// 흔들림을 펴는 시간 폭(초). 세기 0이면 0.3초, 1이면 3초.
    var smoothingWindow: Double {
        0.3 + strength * 2.7
    }
}

/// 원본 영상의 프레임마다 누적 움직임(#71). 화면 크기에 대한 비율이고, 오른쪽·위(Core Image 좌표)로 움직였으면 양수다.
/// 기기 안에서 분석해(Vision 프레임 정합) 앱 캐시에 둔다.
nonisolated struct MotionPath {
    /// 프레임 시각(원본 초, 오름차순).
    var times: [Double]
    var x: [Double]
    var y: [Double]

    /// 보정으로 확대할 수 있는 최대 배율. 이보다 크게 흔들리면 가장자리가 조금 보일 수 있다.
    static let maximumZoom = 1.3
}

nonisolated extension MotionPath: Equatable {}

// MARK: - Queries

nonisolated extension MotionPath {
    /// `time`(원본 초)에 화면을 옮길 만큼(화면 비율). 고르게 편 경로와 실제 경로의 차이라, 흔들려 튄 만큼 반대로 되돌린다.
    func correction(at time: Double, window: Double) -> (x: Double, y: Double) {
        guard let index = nearestIndex(to: time) else { return (0, 0) }
        let smoothed = smoothedPoint(at: index, window: window)
        return (smoothed.x - x[index], smoothed.y - y[index])
    }

    /// `range`(원본 초) 동안 보정해도 가장자리가 보이지 않게 할 확대 배율. 확대한 화면을 옮기므로 옮기는 양도 배율만큼 커져,
    /// 가장 크게 옮기는 비율이 `c`면 `1 / (1 - 2c)`다(최대 130%).
    func zoom(during range: ClosedRange<Double>, window: Double) -> Double {
        let indices = times.indices.filter { range.contains(times[$0]) }
        let largest = indices.map { index -> Double in
            let smoothed = smoothedPoint(at: index, window: window)
            return max(abs(smoothed.x - x[index]), abs(smoothed.y - y[index]))
        }.max() ?? 0
        guard largest * 2 < 1 else { return Self.maximumZoom }
        return min(1 / (1 - largest * 2), Self.maximumZoom)
    }

    /// `index` 프레임 앞뒤 `window`초(절반씩) 평균. 처음·끝 근처는 있는 프레임만 쓴다.
    private func smoothedPoint(at index: Int, window: Double) -> (x: Double, y: Double) {
        let half = window / 2
        let center = times[index]
        var lower = index
        while lower > 0, center - times[lower - 1] <= half {
            lower -= 1
        }
        var upper = index
        while upper < times.count - 1, times[upper + 1] - center <= half {
            upper += 1
        }
        let count = Double(upper - lower + 1)
        return (x[lower ... upper].reduce(0, +) / count, y[lower ... upper].reduce(0, +) / count)
    }

    /// `time`에 가장 가까운 프레임.
    private func nearestIndex(to time: Double) -> Int? {
        guard !times.isEmpty else { return nil }
        var low = 0
        var high = times.count - 1
        while low < high {
            let middle = (low + high) / 2
            if times[middle] < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low > 0, abs(times[low - 1] - time) < abs(times[low] - time) {
            return low - 1
        }
        return low
    }
}
