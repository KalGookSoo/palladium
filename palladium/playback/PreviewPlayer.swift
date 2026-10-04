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
    /// 미리보기에서 듣는 소리 크기(0~1). 결과물에는 영향이 없고 저장하지 않는다(#44).
    private(set) var volume: Float = 1
    private(set) var isMuted = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var requestedURL: URL?

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

    /// 로드 중에 다른 원본이 선택되면 호출한 Task가 취소되므로, 취소된 결과는 반영하지 않는다.
    /// 화면이 다시 만들어지며 같은 원본을 또 요청해도 다시 로드하지 않는다.
    func load(url: URL?) async {
        guard url != requestedURL else { return }
        requestedURL = url

        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTime = .zero

        guard let url else {
            loadState = .empty
            return
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            Logger.playback.error("재생할 파일이 없음: \(url.lastPathComponent, privacy: .public)")
            loadState = .unavailable
            return
        }

        loadState = .loading
        let asset = AVURLAsset(url: url)
        do {
            let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
            let frameDuration = try await Self.frameDuration(of: asset)
            guard !Task.isCancelled else { return }
            guard isPlayable else {
                loadState = .unavailable
                return
            }
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            loadState = .ready(PlaybackTimeline(duration: duration, frameDuration: frameDuration))
            Logger.playback.info("미리보기 로드: \(url.lastPathComponent, privacy: .public)")
        } catch {
            guard !Task.isCancelled else { return }
            Logger.playback.error("미리보기 로드 실패: \(error.localizedDescription, privacy: .public)")
            loadState = .unavailable
        }
    }

    func togglePlayPause() {
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
        isPlaying = player.rate != 0
    }

    /// 0~1 밖의 값은 가장 가까운 값으로 맞춘다. 음량을 올리면 음소거를 푼다.
    func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0), 1)
        player.volume = volume
        if volume > 0, isMuted {
            isMuted = false
            player.isMuted = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
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

    private static func frameDuration(of asset: AVURLAsset) async throws -> CMTime? {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let minFrameDuration = try await videoTrack.load(.minFrameDuration)
        return minFrameDuration.isNumeric && minFrameDuration > .zero ? minFrameDuration : nil
    }
}
