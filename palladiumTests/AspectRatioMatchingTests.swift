import CoreGraphics
@testable import palladium
import Testing

struct AspectRatioMatchingTests {
    @Test("원본 크기에 가장 가까운 화면비를 고른다(세로 영상은 9:16, 정사각형에 가까우면 1:1)")
    func closestPreset() {
        #expect(AspectRatioPreset.closest(to: CGSize(width: 1080, height: 1920)) == .portrait9x16)
        #expect(AspectRatioPreset.closest(to: CGSize(width: 3840, height: 2160)) == .landscape16x9)
        #expect(AspectRatioPreset.closest(to: CGSize(width: 1440, height: 1080)) == .square1x1)
        #expect(AspectRatioPreset.closest(to: CGSize(width: 2400, height: 1080)) == .landscape16x9)
        #expect(AspectRatioPreset.closest(to: .zero) == nil)
    }

    @Test("여러 원본이 섞이면 타임라인에서 더 오래 차지하는 방향을 권한다")
    func suggestedPresetIsWeightedByDuration() {
        let portrait = CGSize(width: 1080, height: 1920)
        let landscape = CGSize(width: 1920, height: 1080)
        #expect(AspectRatioPreset.suggested(for: [(portrait, 10), (landscape, 3)]) == .portrait9x16)
        #expect(AspectRatioPreset.suggested(for: [(portrait, 2), (landscape, 3)]) == .landscape16x9)
        #expect(AspectRatioPreset.suggested(for: []) == nil)
    }

    @Test("고른 화면비가 원본 방향과 다를 때만 내보내기 경고를 낸다")
    @MainActor
    func exportWarning() throws {
        let warning = try #require(MainWindowView.aspectRatioWarning(chosen: .landscape16x9, suggested: .portrait9x16))
        #expect(warning.contains("세로 영상") && warning.contains("9:16"))
        #expect(MainWindowView.aspectRatioWarning(chosen: .portrait9x16, suggested: .portrait9x16) == nil)
        #expect(MainWindowView.aspectRatioWarning(chosen: .portrait9x16, suggested: nil) == nil)
    }
}
