import CoreGraphics
import CoreMedia
import Foundation

/// 내보내기 영상 코덱. 컨테이너는 어디서나 열리는 MP4로 고정한다.
nonisolated enum ExportCodec: String, CaseIterable {
    /// 호환성이 가장 좋다.
    case h264
    /// 같은 화질에 파일이 절반 정도로 작다. 아이폰 원본과 같은 코덱이다.
    case hevc

    static let defaultValue = ExportCodec.h264

    var title: String {
        switch self {
        case .h264: "H.264 (호환성 우선)"
        case .hevc: "HEVC (작은 파일)"
        }
    }
}

/// 결과물 해상도(화면비의 짧은 변). 기본은 원본을 따른다.
nonisolated enum ExportResolution: String, CaseIterable {
    /// 시퀀스에 쓰인 가장 큰 영상의 짧은 변(최대 2160). 영상이 없으면 1080.
    case source
    case hd720
    case hd1080
    case uhd

    static let defaultValue = ExportResolution.source
    /// 원본을 따를 때의 최대 짧은 변(4K).
    static let maximumShortSide = 2160.0

    var title: String {
        switch self {
        case .source: "원본과 같게"
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd: "4K"
        }
    }

    /// 정해진 짧은 변. 원본을 따르면 `nil`.
    var fixedShortSide: Double? {
        switch self {
        case .source: nil
        case .hd720: 720
        case .hd1080: 1080
        case .uhd: 2160
        }
    }
}

/// 원본 영상 하나의 프레임 정보.
nonisolated struct SourceFrameTiming {
    /// 평균 프레임레이트. 아이폰처럼 프레임 간격이 흔들리는 영상은 59.95처럼 정수에서 조금 벗어난다.
    let nominalFrameRate: Float
    /// 가장 짧은 프레임 간격. 아이폰은 정확히 1/60초처럼 기록 단위가 드러난다.
    let minFrameDuration: CMTime
}

/// 결과물 프레임 간격. 원본 영상의 프레임레이트를 따라가 프레임이 줄지 않게 한다.
nonisolated enum OutputFrameRate {
    /// 영상이 없을 때(이미지·자막만) 쓰는 30fps.
    static let defaultDuration = CMTime(value: 1, timescale: 30)
    /// 정수 프레임레이트. 60fps를 넘는 원본(슬로모션 촬영 등)은 60fps로 낸다.
    static let integerRates: [Int32] = [24, 25, 30, 50, 60]
    /// 23.976·29.97·59.94fps의 정확한 프레임 간격. 원본의 가장 짧은 프레임 간격이 이 값과 정확히 같을 때만 쓴다.
    static let fractionalDurations = [
        CMTime(value: 1001, timescale: 24000),
        CMTime(value: 1001, timescale: 30000),
        CMTime(value: 1001, timescale: 60000),
    ]

    /// 원본들 중 가장 높은 프레임레이트의 프레임 간격. 알 수 없으면 30fps.
    static func frameDuration(forSources sources: [SourceFrameTiming]) -> CMTime {
        sources.map(frameDuration(for:)).min() ?? defaultDuration
    }

    /// 원본 하나의 프레임 간격. 평균이 정수에서 조금 벗어나도(59.95) 프레임이 줄지 않도록, 원본보다 낮지 않은
    /// 가장 가까운 정수 프레임레이트(60)를 고른다. 23.976 계열은 원본 기록 간격이 정확히 그 값일 때만 그대로 쓴다.
    static func frameDuration(for source: SourceFrameTiming) -> CMTime {
        if let exact = fractionalDurations.first(where: { CMTimeCompare($0, source.minFrameDuration) == 0 }) {
            return exact
        }
        var rate = Double(source.nominalFrameRate)
        if rate <= 0, source.minFrameDuration.isNumeric, source.minFrameDuration > .zero {
            rate = 1 / source.minFrameDuration.seconds
        }
        guard rate > 0 else { return defaultDuration }
        // 평균값의 흔들림(±0.1fps)은 같은 프레임레이트로 본다.
        let chosen = integerRates.first { Double($0) >= rate - 0.1 } ?? integerRates[integerRates.count - 1]
        return CMTime(value: 1, timescale: chosen)
    }
}

/// 내보내기 화질(#77). 단계를 고르면 해상도·프레임레이트·코덱으로 비트레이트를 계산하고, "직접 입력"이면 Mbit/s를 그대로 쓴다.
nonisolated enum ExportQuality: String, CaseIterable {
    /// 시퀀스에 쓰인 영상 원본 중 가장 높은 비트레이트(알 수 없으면 "높음").
    case source
    case high
    case medium
    case small
    /// Mbit/s를 직접 넣는다.
    case custom

    static let defaultValue = ExportQuality.source

    var title: String {
        switch self {
        case .source: "원본과 비슷하게"
        case .high: "높음"
        case .medium: "보통"
        case .small: "작게"
        case .custom: "직접 입력"
        }
    }
}

/// 내보내기 비트레이트 계산(#77). 픽셀 하나·프레임 하나에 쓰는 비트(bpp)를 단계마다 정해 두고 화면 크기·프레임레이트를 곱한다.
/// H.264 "높음"은 1080p 30fps에서 약 9Mbit/s(유튜브 권장 8Mbit/s보다 조금 높게)이고, HEVC는 같은 화질에 60%만 쓴다.
/// 프레임레이트는 30fps를 기준으로 0.6제곱만큼만 늘린다(60fps는 약 1.5배 — 유튜브 권장 비율과 비슷하다).
nonisolated enum ExportBitRate {
    static let minimumMbps = 1.0
    static let maximumMbps = 200.0
    static let defaultCustomMbps = 20.0
    private static let hevcFactor = 0.6

    static func bitsPerPixel(_ quality: ExportQuality) -> Double {
        switch quality {
        case .source, .high: 0.15
        case .medium: 0.09
        case .small: 0.05
        case .custom: 0.15
        }
    }

    /// 초당 비트 수. `sourceBitRate`는 원본 중 가장 높은 비트레이트(초당 비트, 모르면 `nil`)다. 결과는 1~200Mbit/s 사이로 맞춘다.
    static func bitsPerSecond(
        quality: ExportQuality,
        codec: ExportCodec,
        renderSize: CGSize,
        frameDuration: CMTime,
        sourceBitRate: Double?,
        customMbps: Double
    ) -> Double {
        let value: Double
        switch quality {
        case .custom:
            value = customMbps * 1_000_000
        case .source where (sourceBitRate ?? 0) > 0:
            value = sourceBitRate ?? 0
        default:
            let fps = frameDuration.isNumeric && frameDuration > .zero ? 1 / frameDuration.seconds : 30
            let pixels = Double(renderSize.width * renderSize.height)
            let codecFactor = codec == .hevc ? hevcFactor : 1
            value = pixels * 30 * pow(fps / 30, 0.6) * bitsPerPixel(quality) * codecFactor
        }
        return min(max(value, minimumMbps * 1_000_000), maximumMbps * 1_000_000)
    }
}
