@testable import palladium
import Testing

struct HelpSearchTests {
    @Test("검색어가 없으면 모든 안내와 단축키가 보인다")
    func emptyQueryMatchesEverything() {
        let search = HelpSearch(query: "  ")
        #expect(HelpContent.topics.allSatisfy(search.matches))
        #expect(ShortcutGuide.sections.flatMap(\.entries).allSatisfy(search.matches))
    }

    @Test("안내는 제목·본문으로, 단축키는 이름·설명·키로 찾는다")
    func queryMatchesTitlesBodiesAndKeys() {
        #expect(HelpContent.topics.filter(HelpSearch(query: "백업").matches).map(\.title) == ["프로젝트"])
        #expect(HelpSearch(query: "⌘B").matches(ShortcutGuide.splitAtPlayhead))
        #expect(HelpSearch(query: "리플").matches(ShortcutGuide.rippleDeleteClips))
        #expect(!HelpSearch(query: "리플").matches(ShortcutGuide.save))
    }
}
