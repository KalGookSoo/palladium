import CoreGraphics
import Foundation

/// 결과물 화면비. 원시값은 환경설정의 기본 화면비를 저장하는 데 쓴다.
nonisolated enum AspectRatioPreset: String, CaseIterable {
    case landscape16x9
    case portrait9x16
    case square1x1
}

// MARK: - Queries

nonisolated extension AspectRatioPreset {
    var widthRatio: Int {
        switch self {
        case .landscape16x9: 16
        case .portrait9x16: 9
        case .square1x1: 1
        }
    }

    var heightRatio: Int {
        switch self {
        case .landscape16x9: 9
        case .portrait9x16: 16
        case .square1x1: 1
        }
    }
}

nonisolated extension AspectRatioPreset: Identifiable {
    var id: Self {
        self
    }
}

// MARK: - Matching sources

nonisolated extension AspectRatioPreset {
    /// 화면에 보이는 크기가 `size`인 원본에 가장 가까운 화면비(가로세로 비의 로그 차이가 가장 작은 것).
    static func closest(to size: CGSize) -> AspectRatioPreset? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = log(Double(abs(size.width / size.height)))
        return allCases.min { abs(log($0.ratio) - ratio) < abs(log($1.ratio) - ratio) }
    }

    /// 원본 영상·이미지들(화면 크기와 타임라인 길이)에 맞는 화면비. 길이로 가중해 가장 많이 차지하는 화면비다.
    static func suggested(for contents: [(size: CGSize, duration: Double)]) -> AspectRatioPreset? {
        var weights: [AspectRatioPreset: Double] = [:]
        for content in contents {
            if let preset = closest(to: content.size) {
                weights[preset, default: 0] += max(content.duration, 0)
            }
        }
        return weights.max { $0.value < $1.value }?.key
    }

    /// 가로 ÷ 세로.
    var ratio: Double {
        Double(widthRatio) / Double(heightRatio)
    }

    var title: String {
        "\(widthRatio):\(heightRatio)"
    }

    /// 원본 방향을 사람이 읽는 말로. 예: "세로 영상"
    var orientationTitle: String {
        switch self {
        case .landscape16x9: "가로 영상"
        case .portrait9x16: "세로 영상"
        case .square1x1: "정사각형 영상"
        }
    }
}

