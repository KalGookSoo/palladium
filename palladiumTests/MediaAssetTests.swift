@testable import palladium
import Testing

struct MediaAssetTests {
    @Test("별점은 0부터 5까지로 맞춘다")
    func ratingIsClamped() {
        var asset = SampleData.introVideo
        asset.rate(3)
        #expect(asset.rating == 3)
        asset.rate(9)
        #expect(asset.rating == 5)
        asset.rate(-1)
        #expect(asset.rating == 0)
    }

    @Test("태그는 쉼표로 나누고 공백·빈 태그·대소문자만 다른 중복을 뺀다")
    func tagsAreParsedFromCommaSeparatedText() {
        var asset = SampleData.introVideo
        asset.setTags(from: " 인터뷰, B컷,, b컷 ,야외 ")
        #expect(asset.tags == ["인터뷰", "B컷", "야외"])
        asset.setTags(from: "  ")
        #expect(asset.tags.isEmpty)
    }
}
