import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import Testing

/// 미리보기 재생 상태(#88). 실제 AVPlayer로 짧은 시퀀스를 끝까지 재생해 본다.
@MainActor
struct PreviewPlayerTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    /// 0.5초짜리 영상 하나를 놓은 시퀀스를 불러온 플레이어.
    private func loadedPlayer() async throws -> PreviewPlayer {
        let url = try await TestMedia.makeVideo(red: 0, green: 255, blue: 0, seconds: 0.5)
        let asset = MediaAsset(id: UUID(), name: "green.mov", sourceURL: url, kind: .video, duration: seconds(0.5))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(asset.makeClip(at: .zero)), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [asset], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let player = PreviewPlayer()
        player.loadSequence(composition)
        try await waitUntil { player.player.currentItem?.status == .readyToPlay }
        return player
    }

    /// 조건이 맞을 때까지 기다린다(최대 `timeout`초). 시간을 넘기면 테스트를 실패시킨다.
    private func waitUntil(timeout: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else {
                Issue.record("기다리던 상태가 \(timeout)초 안에 오지 않았다")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("끝까지 재생하면 재생 중이 아니고 끝에 있다고 알리며, 그때 재생하면 처음부터 다시 재생한다")
    func replaysFromStartAtEnd() async throws {
        let player = try await loadedPlayer()

        player.togglePlayPause()
        #expect(player.isPlaying)
        try await waitUntil { !player.isPlaying }
        #expect(player.isAtEnd)

        player.togglePlayPause()
        #expect(player.isPlaying)
        #expect(!player.isAtEnd)
        #expect(player.currentTime.seconds < 0.2)
        player.pause()
    }

    @Test("끝이 아닌 곳에서는 재생과 일시정지를 오간다")
    func togglesInTheMiddle() async throws {
        let player = try await loadedPlayer()
        guard case let .ready(timeline) = player.loadState else {
            Issue.record("시퀀스를 불러오지 못했다")
            return
        }
        player.seek(to: seconds(0.1), in: timeline)
        #expect(!player.isAtEnd)

        player.togglePlayPause()
        #expect(player.isPlaying)
        player.togglePlayPause()
        #expect(!player.isPlaying)
        #expect(!player.isAtEnd)
        #expect(player.currentTime.seconds < 0.4)
    }

    @Test("내레이션처럼 위치를 지켜야 할 때는 끝에 있어도 처음으로 돌아가지 않는다")
    func playWithoutRestartKeepsPosition() async throws {
        let player = try await loadedPlayer()
        player.togglePlayPause()
        try await waitUntil { !player.isPlaying }
        #expect(player.isAtEnd)

        player.play(restartsAtEnd: false)
        #expect(player.isAtEnd)
        player.pause()
    }
}
