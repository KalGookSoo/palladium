import CoreGraphics
import CoreMedia
import Foundation

/// 결과물 화면의 고정된 영역을 정해진 시간 동안 흐리거나 모자이크로 가린다(#59). 피사체를 따라가지 않는다.
nonisolated struct Mask {
    let id: UUID
    var range: CMTimeRange
    var area = MaskArea()
    var shape = MaskShape.rectangle
    var effect = MaskEffect.blur
    /// 가리는 세기(0~1). 블러 반경·모자이크 칸 크기가 커진다.
    var strength = 0.5

    static let defaultDuration = CMTime(value: 3, timescale: 1)
    static let minimumDuration = CMTime(value: 1, timescale: 10)
}

/// 가릴 영역. 화면 너비·높이에 대한 비율이며 원점은 왼쪽 위다.
nonisolated struct MaskArea {
    var centerX = 0.5
    var centerY = 0.5
    var width = 0.3
    var height = 0.3

    static let sizeRange = 0.02 ... 1.0

    /// 화면 크기(`renderSize`) 안에서 영역이 차지하는 사각형(왼쪽 위 원점).
    func rect(in renderSize: CGSize) -> CGRect {
        CGRect(
            x: (centerX - width / 2) * renderSize.width,
            y: (centerY - height / 2) * renderSize.height,
            width: width * renderSize.width,
            height: height * renderSize.height
        )
    }

    /// 크기는 범위 안으로, 가운데는 화면 안으로 맞춘다.
    mutating func clamp() {
        width = min(max(width, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        height = min(max(height, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        centerX = min(max(centerX, 0), 1)
        centerY = min(max(centerY, 0), 1)
    }
}

nonisolated enum MaskShape: String, CaseIterable {
    case rectangle
    case ellipse
}

nonisolated enum MaskEffect: String, CaseIterable {
    case blur
    case mosaic

    var title: String {
        switch self {
        case .blur: "블러"
        case .mosaic: "모자이크"
        }
    }
}

nonisolated extension Mask: Identifiable {}
nonisolated extension Mask: Equatable {}
nonisolated extension MaskArea: Equatable {}

// MARK: - EditSequence

nonisolated extension EditSequence {
    /// `time`부터 기본 길이(3초) 동안 화면 가운데를 흐리는 마스크를 둔다.
    @discardableResult
    mutating func addMask(at time: CMTime) -> Mask.ID {
        let mask = Mask(id: UUID(), range: CMTimeRange(start: CMTimeMaximum(time, .zero), duration: Mask.defaultDuration))
        masks.append(mask)
        masks.sort { $0.range.start < $1.range.start }
        return mask.id
    }

    /// 영역·모양·효과·세기를 바꾼다(시간은 `setMaskRange`). 영역과 세기는 범위 안으로 맞춘다.
    mutating func updateMask(_ mask: Mask) {
        guard let index = masks.firstIndex(where: { $0.id == mask.id }) else { return }
        var updated = mask
        updated.range = masks[index].range
        updated.area.clamp()
        updated.strength = min(max(mask.strength, 0), 1)
        masks[index] = updated
    }

    /// 시작이 0보다 앞서지 않고 최소 길이는 남도록 맞춘다.
    mutating func setMaskRange(_ maskID: Mask.ID, start: CMTime, end: CMTime) {
        guard let index = masks.firstIndex(where: { $0.id == maskID }) else { return }
        let clampedStart = CMTimeMaximum(start, .zero)
        masks[index].range = CMTimeRange(start: clampedStart, end: CMTimeMaximum(end, clampedStart + Mask.minimumDuration))
        masks.sort { $0.range.start < $1.range.start }
    }

    mutating func removeMask(_ maskID: Mask.ID) {
        masks.removeAll { $0.id == maskID }
    }
}
