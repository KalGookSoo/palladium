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
    /// 재생이 실제로 멈췄는지 본다. 시퀀스 끝(`forwardPlaybackEndTime`)에서 멈추면 주기 관찰자가 더 불리지 않아
    /// 재생 중으로 남는 것을 막는다(#88).
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time
                self?.isPlaying = self?.player.rate != 0
            }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, player.timeControlStatus == .paused else { return }
                    self.isPlaying = false
                    // 끝에서 멈췄을 때만 위치를 끝으로 맞춘다. 프레임 이동(멈춘 뒤 옮기기) 중에는 늦게 온 알림이
                    // 옮긴 위치를 예전 위치로 되돌리지 않게 건드리지 않는다.
                    let now = player.currentTime()
                    if let end = player.currentItem?.forwardPlaybackEndTime, end.isNumeric,
                       now >= end - CMTime(value: 1, timescale: 120)
                    {
                        self.currentTime = now
                    }
                }
            }
        }
    }

    // MARK: - Queries

    /// 시퀀스 끝에 있는지(반 프레임 이내). 끝에서 재생하면 처음부터 다시 재생한다(#88).
    var isAtEnd: Bool {
        guard case let .ready(timeline) = loadState else { return false }
        let halfFrame = CMTimeMultiplyByRatio(timeline.frameDuration ?? OutputFrameRate.defaultDuration, multiplier: 1, divisor: 2)
        return currentTime >= timeline.duration - halfFrame
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
        let timeline = PlaybackTimeline(duration: composition.duration, frameDuration: composition.frameDuration)
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

    /// 재생 중이면 멈추고, 멈춰 있으면 재생한다. 끝에 있으면 처음부터 다시 재생한다(버튼·Space 공통).
    func togglePlayPause() {
        if player.rate == 0 {
            play()
        } else {
            pause()
        }
    }

    func setMutedForRecording(_ muted: Bool) {
        isMutedForRecording = muted
        player.isMuted = muted
    }

    /// 끝에 있으면 처음으로 옮긴 뒤 재생한다. 내레이션 녹음처럼 지금 위치를 지켜야 하면 `restartsAtEnd`를 끈다.
    func play(restartsAtEnd: Bool = true) {
        if restartsAtEnd, isAtEnd {
            seek(to: .zero)
        }
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
