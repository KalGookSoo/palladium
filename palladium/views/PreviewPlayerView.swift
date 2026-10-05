import OSLog
import SwiftUI

/// 시퀀스(결과물)를 재생한다. 원본 전용 미리보기는 두지 않고, 원본 확인은 훑어보기(Quick Look) 창으로 한다(#5).
/// 타임라인을 숨기거나 보일 때도 재생이 끊기지 않도록 플레이어와 로드 명령은 상위(`MainWindowView`)가 소유한다.
struct PreviewPlayerView: View {
    let previewPlayer: PreviewPlayer
    /// 프로젝트에 원본이 하나도 없으면 가져오기부터 안내한다.
    let hasProjectAssets: Bool
    /// 타임라인에서 고른 클립(화면에 그려지는 영상·이미지 하나). 있으면 미리보기 위에 테두리와 손잡이를 그린다.
    var transformTarget: (clip: Clip, asset: MediaAsset)?
    var renderSize = SequenceComposer.renderSize(for: .landscape16x9)
    var setTransform: (Clip.ID, ClipTransform) -> Void = { _, _ in }
    @State private var targetContentSize: CGSize?

    var body: some View {
        switch previewPlayer.loadState {
        case .empty:
            ContentUnavailableView(
                "시퀀스가 비어 있음",
                systemImage: "play.rectangle",
                description: Text(hasProjectAssets ? "미디어 패널에서 원본을 타임라인으로 끌어다 놓으세요" : "⌘I로 미디어를 가져오세요")
            )
        case .loading:
            ProgressView()
        case .unavailable:
            ContentUnavailableView("재생할 수 없음", systemImage: "exclamationmark.triangle")
        case let .ready(timeline):
            VStack(spacing: 0) {
                PlayerSurfaceView(player: previewPlayer.player)
                    .overlay {
                        if let transformTarget, let targetContentSize {
                            TransformHandlesView(
                                transform: transformTarget.clip.transform,
                                contentSize: targetContentSize,
                                renderSize: renderSize
                            ) { setTransform(transformTarget.clip.id, $0) }
                        }
                    }
                    .task(id: transformTarget?.asset.id) {
                        targetContentSize = nil
                        if let asset = transformTarget?.asset {
                            targetContentSize = await ClipContentProvider.shared.contentSize(for: asset)
                        }
                    }
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

                HStack {
                    Button(action: requestNarrationRecording) {
                        Label("내레이션 녹음", systemImage: "mic.fill")
                    }
                    .help(ShortcutGuide.narration.helpText)

                    VolumeControl(previewPlayer: previewPlayer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .padding()
    }
}

/// 미리보기에서 듣는 소리만 바꾼다(결과물 음량은 오디오 믹싱 #44 2단계).
private struct VolumeControl: View {
    let previewPlayer: PreviewPlayer

    var body: some View {
        let volume = Binding<Double>(
            get: { previewPlayer.isMuted ? 0 : Double(previewPlayer.volume) },
            set: { previewPlayer.setVolume(Float($0)) }
        )

        HStack(spacing: 4) {
            Button(action: previewPlayer.toggleMute) {
                Label(previewPlayer.isMuted ? "음소거 해제" : "음소거", systemImage: speakerSymbol)
            }
            .help(previewPlayer.isMuted ? "음소거 해제 — 미리보기 소리를 다시 켭니다" : "음소거 — 미리보기 소리를 끕니다")

            Slider(value: volume, in: 0 ... 1)
                .controlSize(.mini)
                .frame(width: 70)
                .accessibilityLabel("미리보기 음량")
                .help("미리보기 음량 — 지금 듣는 소리만 바꾸고 결과물에는 영향이 없습니다")
        }
    }

    private var speakerSymbol: String {
        if previewPlayer.isMuted || previewPlayer.volume == 0 {
            return "speaker.slash.fill"
        }
        return previewPlayer.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
    }
}

private func requestNarrationRecording() {
    Logger.narration.info("내레이션 녹음 요청: 아직 구현되지 않음")
}

#Preview {
    @Previewable @State var previewPlayer = PreviewPlayer()
    PreviewPlayerView(previewPlayer: previewPlayer, hasProjectAssets: true)
}
