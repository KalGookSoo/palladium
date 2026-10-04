import OSLog
import SwiftUI

/// 타임라인을 숨기거나 보일 때도 재생이 끊기지 않도록 플레이어와 로드 명령은 상위(`MainWindowView`)가 소유한다.
struct PreviewPlayerView: View {
    let asset: MediaAsset?
    let previewPlayer: PreviewPlayer
    /// 프로젝트에 원본이 하나도 없으면 더블클릭할 대상이 없으므로 가져오기부터 안내한다.
    let hasProjectAssets: Bool

    var body: some View {
        switch previewPlayer.loadState {
        case .empty:
            ContentUnavailableView(
                "열린 원본 없음",
                systemImage: "play.rectangle",
                description: Text(hasProjectAssets ? "미디어 패널에서 원본을 더블클릭하세요" : "⌘I로 미디어를 가져오세요")
            )
        case .loading:
            ProgressView()
        case .unavailable:
            ContentUnavailableView(
                "재생할 수 없음",
                systemImage: "exclamationmark.triangle",
                description: Text(asset?.name ?? "")
            )
        case let .ready(timeline):
            VStack(spacing: 0) {
                PlayerSurfaceView(player: previewPlayer.player)
                PlaybackControls(previewPlayer: previewPlayer, timeline: timeline)
            }
        }
    }
}

private struct PlaybackControls: View {
    let previewPlayer: PreviewPlayer
    let timeline: PlaybackTimeline

    var body: some View {
        let progress = Binding<Double>(
            get: { timeline.progress(at: previewPlayer.currentTime) },
            set: { previewPlayer.seek(toProgress: $0, in: timeline) }
        )

        VStack {
            Slider(value: progress, in: 0 ... 1)
                .accessibilityLabel("재생 위치")

            // 양옆 칸이 같은 폭을 나눠 가져 재생 버튼이 정확히 가운데에 온다. 왼쪽 끝은 떠 있는 사이드바에 가려질 수 있어
            // 시간은 버튼 바로 왼쪽에, 내레이션 녹음은 바로 오른쪽에 붙인다.
            HStack {
                Text(timeline.timeLabel(at: previewPlayer.currentTime))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    previewPlayer.stepFrame(by: -1, in: timeline)
                } label: {
                    Label("이전 프레임", systemImage: "backward.frame.fill")
                }
                .disabled(!timeline.canStepFrames)
                .help(ShortcutGuide.previousFrame.helpText)

                Button(action: previewPlayer.togglePlayPause) {
                    Label(
                        previewPlayer.isPlaying ? "일시정지" : "재생",
                        systemImage: previewPlayer.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .help(ShortcutGuide.playPause.helpText)

                Button {
                    previewPlayer.stepFrame(by: 1, in: timeline)
                } label: {
                    Label("다음 프레임", systemImage: "forward.frame.fill")
                }
                .disabled(!timeline.canStepFrames)
                .help(ShortcutGuide.nextFrame.helpText)

                Button(action: requestNarrationRecording) {
                    Label("내레이션 녹음", systemImage: "mic.fill")
                }
                .help(ShortcutGuide.narration.helpText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .padding()
    }
}

private func requestNarrationRecording() {
    Logger.narration.info("내레이션 녹음 요청: 아직 구현되지 않음")
}

#Preview {
    @Previewable @State var previewPlayer = PreviewPlayer()
    PreviewPlayerView(asset: SampleData.introVideo, previewPlayer: previewPlayer, hasProjectAssets: true)
        .task { await previewPlayer.load(url: SampleData.introVideo.sourceURL) }
}
