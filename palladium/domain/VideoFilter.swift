import Foundation

/// 클립에 쌓는 필터형 영상 이펙트의 종류(#68). Core Image 내장 필터로 그린다(기기 안에서만).
nonisolated enum VideoFilterKind: String, CaseIterable {
    /// 흐리게.
    case blur
    /// 선명하게.
    case sharpen
    /// 가장자리를 어둡게.
    case vignette
    /// 흑백 영화 느낌(누아르).
    case noir
    /// 세피아(오래된 사진).
    case sepia
    /// 픽셀화(큰 네모).
    case pixellate
    /// 밝은 곳이 번지는 빛 번짐.
    case bloom
    /// 가운데가 볼록한 렌즈 왜곡.
    case bump
}

/// 클립의 필터 하나(#68). 세기는 0~1이고, 0이면 원본 그대로다.
nonisolated struct VideoFilter: Identifiable {
    let id: UUID
    var kind: VideoFilterKind
    var intensity: Double

    static let defaultIntensity = 0.5

    init(id: UUID = UUID(), kind: VideoFilterKind, intensity: Double = Self.defaultIntensity) {
        self.id = id
        self.kind = kind
        self.intensity = intensity
    }
}

nonisolated extension VideoFilter: Equatable {}

// MARK: - Commands

nonisolated extension VideoFilter {
    /// 세기를 0~1로 맞춘다.
    mutating func clamp() {
        intensity = min(max(intensity, 0), 1)
    }
}

nonisolated extension [VideoFilter] {
    /// 필터 하나를 `offset`만큼 앞(-)·뒤(+)로 옮긴다(쌓는 순서 바꾸기). 범위를 넘으면 그대로다.
    func moving(_ filterID: VideoFilter.ID, by offset: Int) -> [VideoFilter] {
        guard let index = firstIndex(where: { $0.id == filterID }), indices.contains(index + offset) else { return self }
        var moved = self
        moved.swapAt(index, index + offset)
        return moved
    }
}

// MARK: - Clip

nonisolated extension Clip {
    /// 색보정(#61)·필터(#68)·크로마키(#70)가 걸려 있는지. 타임라인 이름 옆 표시를 정한다.
    var hasEffect: Bool {
        !colorAdjustment.isDefault || !filters.isEmpty || chromaKey != nil
    }
}
