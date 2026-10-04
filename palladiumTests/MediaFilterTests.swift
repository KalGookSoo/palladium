@testable import palladium
import Testing

struct MediaFilterTests {
    private let interview: MediaAsset = {
        var asset = SampleData.bRollVideo
        asset.colorLabel = .red
        asset.tags = ["인터뷰"]
        return asset
    }()

    @Test("조건이 없으면 모든 원본이 일치한다")
    func emptyFilterMatchesEverything() {
        #expect(MediaFilter().matches(SampleData.introVideo))
        #expect(MediaFilter(query: "   ").matches(SampleData.introVideo))
    }

    @Test("검색어는 이름이나 태그의 일부와 대소문자 구분 없이 일치한다")
    func queryMatchesNameOrTag() {
        #expect(MediaFilter(query: "ROLL").matches(interview))
        #expect(MediaFilter(query: "인터").matches(interview))
        #expect(!MediaFilter(query: "music").matches(interview))
    }

    @Test("색상 레이블을 고르면 그 색 중 하나인 원본만 일치하고, 레이블 없는 원본은 빠진다")
    func colorLabelsFilter() {
        let filter = MediaFilter(colorLabels: [.red, .blue])
        #expect(filter.matches(interview))
        #expect(!filter.matches(SampleData.introVideo))
        #expect(!MediaFilter(colorLabels: [.green]).matches(interview))
    }

    @Test("여러 조건은 모두 만족해야 일치한다")
    func conditionsAreCombined() {
        #expect(MediaFilter(query: "인터뷰", colorLabels: [.red]).matches(interview))
        #expect(!MediaFilter(query: "인터뷰", colorLabels: [.blue]).matches(interview))
    }
}
