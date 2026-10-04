import AVFoundation
@testable import palladium
import Testing

@MainActor
struct PreviewPlayerVolumeTests {
    @Test("음량은 0~1로 맞추고 플레이어에 반영한다")
    func volumeIsClamped() {
        let player = PreviewPlayer()
        player.setVolume(0.4)
        #expect(player.volume == 0.4)
        #expect(player.player.volume == 0.4)
        player.setVolume(3)
        #expect(player.volume == 1)
        player.setVolume(-1)
        #expect(player.volume == 0)
    }

    @Test("음소거는 켜고 끌 수 있고, 음량을 올리면 음소거가 풀린다")
    func muteToggles() {
        let player = PreviewPlayer()
        player.toggleMute()
        #expect(player.isMuted && player.player.isMuted)
        player.setVolume(0.7)
        #expect(!player.isMuted && !player.player.isMuted)
    }
}
