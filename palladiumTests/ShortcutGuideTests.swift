@testable import palladium
import Testing

struct ShortcutGuideTests {
    @Test("툴팁은 이름 — 설명 (단축키) 형식이고, 단축키가 없으면 괄호를 붙이지 않는다")
    func helpTextFormat() {
        #expect(ShortcutGuide.playPause.helpText == "재생/일시정지 — 미리보기를 재생하거나 멈춥니다(끝에서는 처음부터 다시 재생) (Space)")
        #expect(ShortcutGuide.aspectRatio.helpText == "화면비 — 결과물의 화면비를 고릅니다")
    }

    @Test("단축키 목록에는 단축키가 있는 항목만 있고 같은 단축키가 겹치지 않는다")
    func guideListsUniqueShortcuts() {
        let entries = ShortcutGuide.sections.flatMap(\.entries)
        let keys = entries.compactMap(\.keys)
        #expect(keys.count == entries.count)
        #expect(Set(keys).count == keys.count)
    }
}
