import CoreMedia

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
