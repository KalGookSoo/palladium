import Foundation

/// 클립의 기본 색보정(#61). 기본값은 원본 그대로이고, 합성기가 Core Image `CIColorControls`로 적용한다.
nonisolated struct ColorAdjustment {
    /// 더하는 밝기(-0.5~+0.5). 0이면 그대로.
    var brightness = 0.0
    /// 대비 배율(0.5~1.5). 1이면 그대로.
    var contrast = 1.0
    /// 채도 배율(0~2). 0이면 흑백, 1이면 그대로.
    var saturation = 1.0

    static let brightnessRange = -0.5 ... 0.5
    static let contrastRange = 0.5 ... 1.5
    static let saturationRange = 0.0 ... 2.0
}

// MARK: - Queries

nonisolated extension ColorAdjustment {
    /// 원본 그대로인지. 합성에서 이펙트를 건너뛰고, 타임라인 표시를 정하는 데 쓴다.
    var isDefault: Bool {
        self == ColorAdjustment()
    }
}

// MARK: - Commands

nonisolated extension ColorAdjustment {
    /// 범위를 벗어난 값은 가장 가까운 값으로 맞춘다.
    mutating func clamp() {
        brightness = min(max(brightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
        contrast = min(max(contrast, Self.contrastRange.lowerBound), Self.contrastRange.upperBound)
        saturation = min(max(saturation, Self.saturationRange.lowerBound), Self.saturationRange.upperBound)
    }
}

nonisolated extension ColorAdjustment: Equatable {}
