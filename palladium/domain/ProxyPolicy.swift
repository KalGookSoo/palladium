import CoreGraphics

/// 프록시(저해상도 대체 파일)를 자동으로 만들 원본 해상도 기준(#43). 환경설정에서 고른다.
nonisolated enum ProxyThreshold: String, CaseIterable {
    case off
    /// 짧은 변 1440 이상(QHD 이상).
    case qhd
    /// 짧은 변 2160 이상(4K 이상). 기본값.
    case uhd

    static let defaultValue = ProxyThreshold.uhd

    /// 이 값 이상인 짧은 변(픽셀)이면 프록시를 만든다. 끄면 `nil`.
    var minimumShortSide: Double? {
        switch self {
        case .off: nil
        case .qhd: 1440
        case .uhd: 2160
        }
    }

    var title: String {
        switch self {
        case .off: "만들지 않음"
        case .qhd: "1440p 이상"
        case .uhd: "4K 이상"
        }
    }

    /// 화면에 보이는 크기가 `pixelSize`인 영상에 프록시를 만들지. 세로 영상도 짧은 변으로 비교한다.
    func shouldGenerateProxy(pixelSize: CGSize) -> Bool {
        guard let minimumShortSide else { return false }
        return min(abs(pixelSize.width), abs(pixelSize.height)) >= minimumShortSide
    }
}
