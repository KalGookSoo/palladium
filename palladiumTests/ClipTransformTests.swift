import CoreGraphics
import Foundation
@testable import palladium
import Testing

/// 미리보기 테두리로 클립을 옮기고 크기를 바꾸는 계산(#84). 늘 끌기 시작 때의 값을 기준으로 해 끄는 동안 어긋나지 않아야 한다.
struct ClipTransformTests {
    private let noSnap = CGVector(dx: 0, dy: 0)

    @Test("옮기기는 시작 트랜스폼 기준이라 같은 끌기 값을 여러 번 넣어도 결과가 같다")
    func moveIsRelativeToStart() {
        let start = ClipTransform(centerX: 0.2, centerY: 0.3, scale: 0.5)
        let first = start.moved(by: CGVector(dx: 0.1, dy: -0.1), snap: noSnap).transform
        let second = start.moved(by: CGVector(dx: 0.1, dy: -0.1), snap: noSnap).transform
        #expect(first == second)
        #expect(abs(first.centerX - 0.3) < 1e-9)
        #expect(abs(first.centerY - 0.2) < 1e-9)
        #expect(first.scale == 0.5)
    }

    @Test("가운데 근처면 화면 가운데에 붙고, 멀면 붙지 않는다")
    func moveSnapsToCenter() {
        let start = ClipTransform(centerX: 0.4, centerY: 0.4)
        let snap = CGVector(dx: 0.01, dy: 0.01)
        let near = start.moved(by: CGVector(dx: 0.095, dy: 0.2), snap: snap)
        #expect(near.transform.centerX == 0.5)
        #expect(near.snapped.x)
        #expect(!near.snapped.y)
        #expect(abs(near.transform.centerY - 0.6) < 1e-9)
    }

    @Test("크기는 시작 폭 기준이라 폭을 두 배로 끌면 배율이 정확히 두 배가 되고, 같은 끌기 값은 누적되지 않는다")
    func resizeIsRelativeToStartWidth() {
        let start = ClipTransform(scale: 0.5)
        let doubled = start.resized(widthChange: 100, startWidth: 100)
        #expect(abs(doubled.scale - 1.0) < 1e-9)
        #expect(start.resized(widthChange: 100, startWidth: 100) == doubled)
        let halved = start.resized(widthChange: -50, startWidth: 100)
        #expect(abs(halved.scale - 0.25) < 1e-9)
        #expect(doubled.centerX == start.centerX)
        #expect(doubled.centerY == start.centerY)
    }

    @Test("크기는 배율 범위 끝에서 멈춘다")
    func resizeClampsScale() {
        let start = ClipTransform(scale: 1)
        #expect(start.resized(widthChange: -500, startWidth: 100).scale == ClipTransform.scaleRange.lowerBound)
        #expect(start.resized(widthChange: 10000, startWidth: 100).scale == ClipTransform.scaleRange.upperBound)
    }
}
