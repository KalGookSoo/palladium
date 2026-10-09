import CoreGraphics
import Foundation

/// 영상 화면에서 잘라낼 만큼(크롭, #85). 위·아래·왼쪽·오른쪽을 원본 화면(회전 반영) 크기에 대한 비율(0~1)로 둔다.
/// 원본 항목·파일에는 두지 않고 파생 항목과 타임라인 클립에만 둔다. 클립의 위치·크기(`ClipTransform`)는 잘린 화면을 기준으로 한다.
nonisolated struct ClipCrop {
    var top = 0.0
    var bottom = 0.0
    var left = 0.0
    var right = 0.0

    /// 남는 폭·높이의 최소 비율. 너무 작게 잘라 화면이 사라지지 않게 한다.
    static let minimumVisible = 0.1
}

/// 크롭 테두리의 손잡이. 네 모서리와 네 변.
nonisolated enum CropHandle: CaseIterable {
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// 크롭 비율 프리셋(#85). 고르면 그 비율로 맞추고, 끄는 동안에도 그 비율을 지킨다. "자유"면 마음대로 자른다.
nonisolated enum CropAspect: CaseIterable {
    case free
    case original
    case landscape16x9
    case portrait9x16
    case square1x1
    case portrait4x5
}

// MARK: - Queries

nonisolated extension CropAspect {
    /// 화면 가로÷세로. 자유는 `nil`, 원본은 원본 화면의 비율이다.
    func ratio(contentSize: CGSize) -> Double? {
        switch self {
        case .free: nil
        case .original: contentSize.height > 0 ? contentSize.width / contentSize.height : nil
        case .landscape16x9: 16.0 / 9
        case .portrait9x16: 9.0 / 16
        case .square1x1: 1
        case .portrait4x5: 4.0 / 5
        }
    }
}

nonisolated extension ClipCrop {
    var isDefault: Bool {
        self == ClipCrop()
    }

    /// 남는 영역(원본 화면 비율 좌표, 왼쪽 위 원점).
    var visibleRect: CGRect {
        CGRect(x: left, y: top, width: 1 - left - right, height: 1 - top - bottom)
    }

    init(visibleRect rect: CGRect) {
        self.init(top: rect.minY, bottom: 1 - rect.maxY, left: rect.minX, right: 1 - rect.maxX)
    }

    /// 원본 화면 `size`에서 잘라낸 뒤의 크기.
    func croppedSize(of size: CGSize) -> CGSize {
        CGSize(width: size.width * visibleRect.width, height: size.height * visibleRect.height)
    }

    /// 잘린 화면의 가로÷세로(⇧ 끌기가 지킬 지금 비율). 원본 크기를 모르면 `nil`.
    func aspectRatio(contentSize: CGSize) -> Double? {
        let size = croppedSize(of: contentSize)
        return size.width > 0 && size.height > 0 ? size.width / size.height : nil
    }

    /// 잘린 화면을 `croppedFrame`에 놓을 때 원본 화면 전체가 차지하는 사각형(왼쪽 위 원점). 합성기가 원본을 놓는 데 쓴다.
    func fullFrame(forCroppedFrame croppedFrame: CGRect) -> CGRect {
        let visible = visibleRect
        let width = croppedFrame.width / visible.width
        let height = croppedFrame.height / visible.height
        return CGRect(x: croppedFrame.minX - visible.minX * width, y: croppedFrame.minY - visible.minY * height, width: width, height: height)
    }
}

// MARK: - Commands

nonisolated extension ClipCrop {
    /// 한 변의 자를 비율을 바꾼다(숫자 입력). 반대쪽 변은 그대로 두고, 남는 폭·높이가 최소값보다 작아지지 않게 이 값만 줄인다.
    func setting(_ edge: WritableKeyPath<ClipCrop, Double>, to value: Double) -> ClipCrop {
        let opposite: KeyPath<ClipCrop, Double> = switch edge {
        case \.top: \.bottom
        case \.bottom: \.top
        case \.left: \.right
        default: \.left
        }
        var changed = self
        changed[keyPath: edge] = min(max(value.isFinite ? value : 0, 0), 1 - Self.minimumVisible - self[keyPath: opposite])
        return changed
    }

    /// 0~1 안으로 맞추고, 남는 폭·높이가 최소값(10%)보다 작아지지 않게 오른쪽·아래를 줄인다.
    mutating func clamp() {
        let maximum = 1 - Self.minimumVisible
        let finite = { (value: Double) in value.isFinite ? value : 0 }
        left = min(max(finite(left), 0), maximum)
        right = min(max(finite(right), 0), maximum - left)
        top = min(max(finite(top), 0), maximum)
        bottom = min(max(finite(bottom), 0), maximum - top)
    }

    /// 화면 비율 `ratio`(가로÷세로)로 맞춘다. 지금 남는 영역의 가운데를 지키며 원본 안에 들어가는 가장 큰 사각형이다.
    func fitted(toAspectRatio ratio: Double, contentSize: CGSize) -> ClipCrop {
        guard let unitRatio = Self.unitRatio(ratio, contentSize: contentSize) else { return self }
        let width = unitRatio >= 1 ? 1 : unitRatio
        let height = unitRatio >= 1 ? 1 / unitRatio : 1
        let center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        let x = min(max(center.x - width / 2, 0), 1 - width)
        let y = min(max(center.y - height / 2, 0), 1 - height)
        return ClipCrop(visibleRect: CGRect(x: x, y: y, width: width, height: height))
    }

    /// 손잡이를 `point`(원본 화면 비율 좌표, 왼쪽 위 원점)로 끈 결과. 반대쪽 변·모서리는 그대로다.
    /// `aspectRatio`(가로÷세로)가 있으면 그 비율을 지킨다 — 모서리는 반대 모서리를 기준으로, 변은 다른 방향 가운데를 지키며 길이를 맞춘다.
    func dragging(_ handle: CropHandle, to point: CGPoint, aspectRatio: Double?, contentSize: CGSize) -> ClipCrop {
        let rect = visibleRect
        let minimum = Self.minimumVisible
        let movesLeft = [.left, .topLeft, .bottomLeft].contains(handle)
        let movesRight = [.right, .topRight, .bottomRight].contains(handle)
        let movesTop = [.top, .topLeft, .topRight].contains(handle)
        let movesBottom = [.bottom, .bottomLeft, .bottomRight].contains(handle)

        guard let ratio = aspectRatio, let unitRatio = Self.unitRatio(ratio, contentSize: contentSize) else {
            var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
            if movesLeft {
                minX = min(max(point.x, 0), maxX - minimum)
            }
            if movesRight {
                maxX = max(min(point.x, 1), minX + minimum)
            }
            if movesTop {
                minY = min(max(point.y, 0), maxY - minimum)
            }
            if movesBottom {
                maxY = max(min(point.y, 1), minY + minimum)
            }
            return ClipCrop(visibleRect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }

        // 비율 유지: 폭을 정하면 높이는 폭 ÷ 비율이다(원본 화면 비율 좌표에서).
        let minimumWidth = max(minimum, minimum * unitRatio)
        let movesHorizontally = movesLeft || movesRight
        let movesVertically = movesTop || movesBottom
        // 기준점: 움직이지 않는 쪽. 한 방향만 움직이면 다른 방향은 가운데를 지킨다.
        let anchorX = movesLeft ? rect.maxX : movesRight ? rect.minX : rect.midX
        let anchorY = movesTop ? rect.maxY : movesBottom ? rect.minY : rect.midY
        let availableWidth = movesLeft ? anchorX : movesRight ? 1 - anchorX : 1
        let availableHeight = movesTop ? anchorY : movesBottom ? 1 - anchorY : 1
        let proposedWidth = movesHorizontally ? abs(point.x - anchorX) : 0
        let proposedHeight = movesVertically ? abs(point.y - anchorY) : 0
        let maximumWidth = min(availableWidth, availableHeight * unitRatio)
        // 가장자리에 붙어 비율을 지키며 최소 크기를 남길 수 없으면 바꾸지 않는다.
        guard minimumWidth <= maximumWidth else { return self }
        let width = min(max(max(proposedWidth, proposedHeight * unitRatio), minimumWidth), maximumWidth)
        let height = width / unitRatio

        let x = movesLeft ? anchorX - width : movesRight ? anchorX : min(max(anchorX - width / 2, 0), 1 - width)
        let y = movesTop ? anchorY - height : movesBottom ? anchorY : min(max(anchorY - height / 2, 0), 1 - height)
        return ClipCrop(visibleRect: CGRect(x: x, y: y, width: width, height: height))
    }

    /// 크기는 그대로 두고 남는 영역을 `dx`·`dy`(원본 화면 비율)만큼 옮긴다. 원본 밖으로 나가지 않는다.
    func moved(dx: Double, dy: Double) -> ClipCrop {
        let rect = visibleRect
        let x = min(max(rect.minX + dx, 0), 1 - rect.width)
        let y = min(max(rect.minY + dy, 0), 1 - rect.height)
        return ClipCrop(visibleRect: CGRect(x: x, y: y, width: rect.width, height: rect.height))
    }

    /// 화면 비율(픽셀 가로÷세로)을 원본 화면 비율 좌표의 가로÷세로로 바꾼다.
    private static func unitRatio(_ ratio: Double, contentSize: CGSize) -> Double? {
        guard ratio > 0, ratio.isFinite, contentSize.width > 0, contentSize.height > 0 else { return nil }
        return ratio * contentSize.height / contentSize.width
    }
}

nonisolated extension ClipCrop: Equatable {}
