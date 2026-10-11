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
    /// 클립 가운데를 기준으로 화면에서 시계 방향으로 돌린 각도(도, #66). -180~180.
    var rotation = 0.0

    static let scaleRange = 0.05 ... 4.0
    static let rotationRange = -180.0 ... 180.0
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
    /// 각도는 같은 방향의 -180~180도로 바꾼다(270도 → -90도).
    mutating func clamp() {
        scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        opacity = min(max(opacity, 0), 1)
        rotation = Self.normalizedRotation(rotation)
    }

    /// 90도씩 돌린다(#66, 인스펙터 ↺·↻ 버튼). `clockwise`면 시계 방향.
    func rotatedByQuarterTurn(clockwise: Bool) -> ClipTransform {
        var rotated = self
        rotated.rotation = Self.normalizedRotation(rotation + (clockwise ? 90 : -90))
        return rotated
    }

    /// 미리보기 회전 손잡이를 끌어 정한 각도(#66). 클립 가운데에서 포인터까지의 방향이 위쪽(0도)에서 시계 방향으로 몇 도인지다.
    /// `snapsToStep`이면 15도 단위로 맞춘다(⇧).
    func rotated(toward pointer: CGPoint, around center: CGPoint, snapsToStep: Bool) -> ClipTransform {
        var rotated = self
        let degrees = atan2(pointer.x - center.x, center.y - pointer.y) * 180 / .pi
        rotated.rotation = Self.normalizedRotation(snapsToStep ? (degrees / 15).rounded() * 15 : degrees)
        return rotated
    }

    /// 같은 방향의 -180 초과 ~ 180 이하 각도.
    static func normalizedRotation(_ degrees: Double) -> Double {
        let wrapped = (degrees + 180).truncatingRemainder(dividingBy: 360)
        let result = (wrapped < 0 ? wrapped + 360 : wrapped) - 180
        return result == -180 ? 180 : result
    }

    /// 끌기 시작 때의 트랜스폼을 화면 비율 `offset`만큼 옮긴 결과(#84). 가운데가 화면 가로·세로 가운데에서 `snap`(화면 비율) 안이면 가운데에 붙이고, 붙었는지 함께 돌려준다.
    func moved(by offset: CGVector, snap: CGVector) -> (transform: ClipTransform, snapped: (x: Bool, y: Bool)) {
        var moved = self
        moved.centerX += offset.dx
        moved.centerY += offset.dy
        let snapsX = abs(moved.centerX - 0.5) < snap.dx
        let snapsY = abs(moved.centerY - 0.5) < snap.dy
        if snapsX {
            moved.centerX = 0.5
        }
        if snapsY {
            moved.centerY = 0.5
        }
        return (moved, (snapsX, snapsY))
    }

    /// 끌기 시작 때 폭이 `startWidth`인 테두리를 가운데 기준으로 `widthChange`만큼 넓힌 배율(#84). 폭과 변화량은 같은 단위면 된다.
    func resized(widthChange: Double, startWidth: Double) -> ClipTransform {
        guard startWidth > 0 else { return self }
        var resized = self
        resized.scale = scale * max(startWidth + widthChange, 0) / startWidth
        resized.clamp()
        return resized
    }
}

nonisolated extension ClipTransform: Equatable {}
