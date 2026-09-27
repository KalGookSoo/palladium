@testable import palladium
import Testing

struct MediaAssetTests {
    @Test("검색어가 비어 있거나 공백뿐이면 모든 원본이 일치한다")
    func emptyQueryMatchesEverything() {
        #expect(SampleData.introVideo.matches(nameQuery: ""))
        #expect(SampleData.introVideo.matches(nameQuery: "   "))
    }

    @Test("이름의 일부만 입력해도 대소문자 구분 없이 일치한다")
    func partialQueryMatchesCaseInsensitively() {
        #expect(SampleData.bRollVideo.matches(nameQuery: "ROLL"))
    }

    @Test("이름에 없는 검색어는 일치하지 않는다")
    func unrelatedQueryDoesNotMatch() {
        #expect(!SampleData.introVideo.matches(nameQuery: "music"))
    }
}
