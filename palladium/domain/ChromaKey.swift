import Foundation

/// 크로마키(#70): 그린스크린·블루스크린의 배경색을 투명하게 만들어 아래 트랙과 합성한다.
/// 밝기와 상관없이 색(크로마, YCbCr의 Cb·Cr)만으로 키 색과의 거리를 재 그림자 진 배경도 빠지게 한다.
nonisolated struct ChromaKey {
    /// 빼낼 배경색. 기본은 초록.
    var keyColor = SubtitleRGB(red: 0, green: 1, blue: 0)
    /// 이 거리(0~1) 안의 색은 완전히 투명해진다.
    var tolerance = 0.3
    /// 투명에서 불투명으로 넘어가는 폭(0~1). 클수록 가장자리가 부드럽다.
    var softness = 0.1
    /// 가장자리에 남은 배경색 기운(초록 번짐)을 빼는 정도(0~1).
    var spillSuppression = 0.5

    static let green = SubtitleRGB(red: 0, green: 1, blue: 0)
    static let blue = SubtitleRGB(red: 0, green: 0, blue: 1)
    /// Cb·Cr 평면에서 가장 먼 두 색 사이의 거리. 거리를 0~1로 맞추는 데 쓴다.
    private static let maximumDistance = 1.0
}

nonisolated extension ChromaKey: Equatable {}

// MARK: - Queries

nonisolated extension ChromaKey {
    /// 색 하나(각 0~1)의 불투명도(0 투명 ~ 1 불투명).
    func alpha(red: Double, green: Double, blue: Double) -> Double {
        let distance = Self.chromaDistance(Self.chroma(red, green, blue), Self.chroma(keyColor.red, keyColor.green, keyColor.blue))
        guard softness > 0 else { return distance <= tolerance ? 0 : 1 }
        let progress = (distance - tolerance) / softness
        let clamped = min(max(progress, 0), 1)
        // 부드러운 계단(smoothstep).
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// 배경색 기운을 뺀 색. 키 색 쪽으로 기운 크로마 성분을 `spillSuppression`만큼 덜어 낸다(밝기는 그대로).
    func spillSuppressed(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
        guard spillSuppression > 0 else { return (red, green, blue) }
        let key = Self.chroma(keyColor.red, keyColor.green, keyColor.blue)
        let keyLength = (key.cb * key.cb + key.cr * key.cr).squareRoot()
        guard keyLength > 0 else { return (red, green, blue) }
        let direction = (cb: key.cb / keyLength, cr: key.cr / keyLength)
        let luma = Self.luma(red, green, blue)
        var chroma = Self.chroma(red, green, blue)
        let toward = chroma.cb * direction.cb + chroma.cr * direction.cr
        guard toward > 0 else { return (red, green, blue) }
        chroma.cb -= direction.cb * toward * spillSuppression
        chroma.cr -= direction.cr * toward * spillSuppression
        return Self.rgb(luma: luma, cb: chroma.cb, cr: chroma.cr)
    }

    // MARK: YCbCr(BT.601)

    private static func luma(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    private static func chroma(_ red: Double, _ green: Double, _ blue: Double) -> (cb: Double, cr: Double) {
        let y = luma(red, green, blue)
        return ((blue - y) * 0.564, (red - y) * 0.713)
    }

    private static func chromaDistance(_ lhs: (cb: Double, cr: Double), _ rhs: (cb: Double, cr: Double)) -> Double {
        let distance = ((lhs.cb - rhs.cb) * (lhs.cb - rhs.cb) + (lhs.cr - rhs.cr) * (lhs.cr - rhs.cr)).squareRoot()
        return min(distance / maximumDistance, 1)
    }

    private static func rgb(luma: Double, cb: Double, cr: Double) -> (red: Double, green: Double, blue: Double) {
        let red = luma + cr / 0.713
        let blue = luma + cb / 0.564
        let green = (luma - 0.299 * red - 0.114 * blue) / 0.587
        return (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
    }
}

// MARK: - Commands

nonisolated extension ChromaKey {
    /// 범위를 벗어난 값은 가장 가까운 값으로 맞춘다.
    mutating func clamp() {
        tolerance = min(max(tolerance, 0), 1)
        softness = min(max(softness, 0), 1)
        spillSuppression = min(max(spillSuppression, 0), 1)
        keyColor = keyColor.clamped
    }

    /// Core Image 색 입방체(`CIColorCube`) 자료. 한 변 `size`칸, 칸마다 (r·a, g·a, b·a, a)(미리 곱한 알파)다.
    func colorCube(size: Int) -> [Float] {
        var data = [Float](repeating: 0, count: size * size * size * 4)
        let step = 1 / Double(size - 1)
        var offset = 0
        for blueIndex in 0 ..< size {
            for greenIndex in 0 ..< size {
                for redIndex in 0 ..< size {
                    let red = Double(redIndex) * step
                    let green = Double(greenIndex) * step
                    let blue = Double(blueIndex) * step
                    let alpha = alpha(red: red, green: green, blue: blue)
                    let color = spillSuppressed(red: red, green: green, blue: blue)
                    data[offset] = Float(color.red * alpha)
                    data[offset + 1] = Float(color.green * alpha)
                    data[offset + 2] = Float(color.blue * alpha)
                    data[offset + 3] = Float(alpha)
                    offset += 4
                }
            }
        }
        return data
    }
}
