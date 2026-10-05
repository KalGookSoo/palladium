import AVFoundation
import Observation
import OSLog

/// AVPlayer를 감싸는 얇은 어댑터. 위치 계산은 `PlaybackTimeline`에 맡기고, 여기서는 AVPlayer에 명령을 전달하고 상태를 관찰만 한다.
@Observable
final class PreviewPlayer {
    enum LoadState {
        case empty
        case loading
        case ready(PlaybackTimeline)
        case unavailable
    }

    let player = AVPlayer()
    private(set) var loadState: LoadState = .empty
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    /// 내레이션을 녹음하는 동안 스피커 소리가 마이크로 들어가지 않게 끈다(#10).
    /// 듣는 소리 크기는 Mac의 음량으로 바꾸고, 결과물 음량은 클립·트랙 음량으로 정한다.
    private(set) var isMutedForRecording = false

    @ObservationIgnored private var timeObserver: Any?

    init() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time
                self?.isPlaying = self?.player.rate != 0
            }
        }
    }

    // MARK: - Commands

    /// 시퀀스 합성을 불러온다. 편집으로 다시 합성해도 보던 위치를 이어 간다(시퀀스가 짧아졌으면 끝으로).
    /// `nil`이면(클립이 없으면) 비운다.
    func loadSequence(_ composition: SequenceComposition?) {
        guard let composition else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentTime = .zero
            loadState = .empty
            return
        }
        let wasPlaying = player.rate != 0
        let resumeTime = CMTimeMinimum(currentTime, composition.duration)
        let item = AVPlayerItem(asset: composition.asset)
        item.videoComposition = composition.videoComposition
        item.audioMix = composition.audioMix
        // 재생 속도를 바꾼 클립의 소리가 높낮이를 지키게 한다(#58).
        item.audioTimePitchAlgorithm = .spectral
        // 재생 길이를 시퀀스 길이로 맞춘다(뒤쪽 빈 시간·이미지 자리도 재생되게).
        item.forwardPlaybackEndTime = composition.duration
        player.replaceCurrentItem(with: item)
        let timeline = PlaybackTimeline(duration: composition.duration, frameDuration: SequenceComposer.frameDuration)
        loadState = .ready(timeline)
        seek(to: timeline.clamped(resumeTime))
        if wasPlaying {
            player.play()
        }
    }

    /// 재생 헤드를 옮겼을 때 미리보기도 그 위치를 보여준다.
    func seek(to time: CMTime, in timeline: PlaybackTimeline) {
        seek(to: timeline.clamped(time))
    }

    func togglePlayPause() {
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
        isPlaying = player.rate != 0
    }

    func setMutedForRecording(_ muted: Bool) {
        isMutedForRecording = muted
        player.isMuted = muted
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stepFrame(by frameCount: Int, in timeline: PlaybackTimeline) {
        player.pause()
        seek(to: timeline.steppedTime(from: currentTime, byFrames: frameCount))
    }

    func seek(toProgress progress: Double, in timeline: PlaybackTimeline) {
        seek(to: timeline.time(atProgress: progress))
    }

    // MARK: - Helpers

    private func seek(to time: CMTime) {
        currentTime = time
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
