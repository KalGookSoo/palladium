import CoreMedia
import Foundation
@testable import palladium
import Testing

struct EditSequenceTests {
    @Test("시퀀스 길이는 가장 늦게 끝나는 클립의 끝 시각이다")
    func durationIsLatestClipEnd() {
        // 샘플: 영상 트랙은 18초에, 오디오 트랙도 18초에 끝난다.
        #expect(SampleData.mainSequence.duration == CMTime(seconds: 18, preferredTimescale: standardTimescale))
    }

    @Test("클립이 없는 시퀀스의 길이는 0이다")
    func emptySequenceHasZeroDuration() {
        let sequence = EditSequence(id: UUID(), name: "빈 시퀀스", tracks: [])
        #expect(sequence.duration == .zero)
    }
}
