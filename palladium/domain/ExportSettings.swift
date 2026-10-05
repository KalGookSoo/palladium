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

/// 결과물 프레임 간격. 원본 영상의 프레임레이트를 그대로 따라가 프레임이 줄지 않게 한다.
nonisolated enum OutputFrameRate {
    /// 영상이 없을 때(이미지·자막만) 쓰는 30fps.
    static let defaultDuration = CMTime(value: 1, timescale: 30)
    /// 흔한 프레임레이트의 정확한 프레임 간격(23.976 ~ 60fps). 60fps를 넘는 원본(슬로모션 촬영 등)은 60fps로 낸다.
    static let standardDurations: [CMTime] = [
        CMTime(value: 1001, timescale: 24000),
        CMTime(value: 1, timescale: 24),
        CMTime(value: 1, timescale: 25),
        CMTime(value: 1001, timescale: 30000),
        CMTime(value: 1, timescale: 30),
        CMTime(value: 1, timescale: 50),
        CMTime(value: 1001, timescale: 60000),
        CMTime(value: 1, timescale: 60),
    ]

    /// 원본 프레임레이트들 중 가장 높은 값에 가장 가까운 표준 프레임 간격. 알 수 없으면 30fps.
    static func frameDuration(forSourceFrameRates rates: [Float]) -> CMTime {
        guard let highest = rates.filter({ $0 > 0 }).max() else { return defaultDuration }
        let rate = Double(highest)
        return standardDurations.min { abs(1 / $0.seconds - rate) < abs(1 / $1.seconds - rate) } ?? defaultDuration
    }
}
