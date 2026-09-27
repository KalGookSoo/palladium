@testable import palladium
import Testing

struct SampleDataTests {
    @Test("샘플 시퀀스의 모든 트랙에는 겹치는 클립이 없다")
    func sampleTracksHaveNoOverlap() {
        for track in SampleData.mainSequence.tracks {
            #expect(!track.hasOverlappingClips)
        }
    }
}
