import CoreGraphics
import Foundation

/// 클립을 화면 어디에 얼마나 크게, 얼마나 진하게 그릴지. 위쪽 영상 트랙의 오버레이(로고·이미지·PIP)를 얹는 데 쓴다(#9).
/// 위치는 화면 크기에 대한 비율이라 화면비 프리셋을 바꿔도 같은 자리에 머문다.
nonisolated struct ClipTransform {
    /// 클립 가운데의 가로·세로 위치(0~1, 왼쪽 위가 0).
    var centerX = 0.5
    var centerY = 0.5
    /// 화면에 비율을 지켜 꽉 맞춘 크기 대비 배율.
    var scale = 1.0
    /// 0(투명)~1(불투명).
    var opacity = 1.0

    static let scaleRange = 0.05 ... 4.0
}

// MARK: - Queries

nonisolated extension ClipTransform {
    /// 원본 크기 `contentSize`를 화면 `renderSize`에 그릴 사각형(왼쪽 위 원점). 먼저 화면에 비율을 지켜 맞추고 배율과 위치를 적용한다.
    func frame(contentSize: CGSize, in renderSize: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return .zero }
        let fitScale = min(renderSize.width / contentSize.width, renderSize.height / contentSize.height) * scale
        let size = CGSize(width: contentSize.width * fitScale, height: contentSize.height * fitScale)
        return CGRect(
            x: centerX * renderSize.width - size.width / 2,
            y: centerY * renderSize.height - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Commands

nonisolated extension ClipTransform {
    /// 범위를 벗어난 배율·불투명도는 가장 가까운 값으로 맞춘다. 위치는 화면 밖으로도 둘 수 있다.
    mutating func clamp() {
        scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        opacity = min(max(opacity, 0), 1)
    }
}

nonisolated extension ClipTransform: Equatable {}
