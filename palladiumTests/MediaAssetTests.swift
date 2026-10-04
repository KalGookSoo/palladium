@testable import palladium
import Testing

struct MediaAssetTests {
    @Test("이름을 바꾸면 앞뒤 공백을 빼고, 원본 파일 경로는 그대로다")
    func renameTrimsWhitespace() {
        var asset = SampleData.introVideo
        asset.rename(to: "  오프닝 인사  ")
        #expect(asset.name == "오프닝 인사")
        #expect(asset.sourceURL == SampleData.introVideo.sourceURL)
    }

    @Test("빈 이름으로는 바꾸지 않는다")
    func emptyRenameIsIgnored() {
        var asset = SampleData.introVideo
        asset.rename(to: "   ")
        #expect(asset.name == SampleData.introVideo.name)
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
