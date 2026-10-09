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
    /// 마스크 레인에서 고른 마스크. 있으면 미리보기 위에 영역과 손잡이를 그린다(#59).
    var maskTarget: Mask?
    var setMaskArea: (Mask.ID, MaskArea) -> Void = { _, _ in }
    /// 자막 레인에서 고른 자막. 있으면 미리보기 위에 상자를 그려 끌어 옮긴다(#82).
    var subtitleTarget: Subtitle?
    var setSubtitlePosition: (Subtitle.ID, Double, Double) -> Void = { _, _, _ in }
    /// 내레이션을 녹음 중이면 녹음을 시작한 때(#10).
    var narrationStartedAt: Date?
    var toggleNarration: () -> Void = {}
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
                                // 위치·크기는 잘린 화면(#85)을 기준으로 한다.
                                contentSize: transformTarget.clip.crop.croppedSize(of: targetContentSize),
                                renderSize: renderSize
                            ) { setTransform(transformTarget.clip.id, $0) }
                        }
                        if let maskTarget {
                            MaskHandlesView(mask: maskTarget, renderSize: renderSize) { setMaskArea(maskTarget.id, $0) }
                        }
                        if let subtitleTarget {
                            SubtitleHandlesView(subtitle: subtitleTarget, renderSize: renderSize) { setSubtitlePosition(subtitleTarget.id, $0, $1) }
                        }
                    }
                    .task(id: transformTarget?.asset.id) {
                        targetContentSize = nil
                        if let asset = transformTarget?.asset {
                            targetContentSize = await ClipContentProvider.shared.contentSize(for: asset)
                        }
                    }
                PlaybackControls(
                    previewPlayer: previewPlayer,
                    timeline: timeline,
                    narrationStartedAt: narrationStartedAt,
                    toggleNarration: toggleNarration
                )
            }
        }
    }
}

private struct PlaybackControls: View {
    let previewPlayer: PreviewPlayer
    let timeline: PlaybackTimeline
    let narrationStartedAt: Date?
    let toggleNarration: () -> Void

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
                    Button(action: toggleNarration) {
                        if narrationStartedAt == nil {
                            Label("내레이션 녹음", systemImage: "mic.fill")
                        } else {
                            Label("녹음 정지", systemImage: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .help(ShortcutGuide.narration.helpText)
                    if let narrationStartedAt {
                        // 녹음한 시간. 스피커로 듣고 있으면 소리가 꺼져 있다는 것도 함께 알린다.
                        TimelineView(.periodic(from: narrationStartedAt, by: 1)) { context in
                            Text(Duration.seconds(context.date.timeIntervalSince(narrationStartedAt)).formatted(.time(pattern: .minuteSecond)))
                                .font(.callout)
                                .foregroundStyle(.red)
                                .monospacedDigit()
                        }
                        .help(previewPlayer.isMutedForRecording
                            ? "녹음 중 — 스피커 소리가 마이크에 들어가지 않도록 미리보기 소리를 껐습니다. 헤드폰을 연결하면 들으며 녹음할 수 있습니다"
                            : "녹음 중 — 헤드폰으로 원본 소리를 들려줍니다")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .padding()
    }
}

#Preview {
    @Previewable @State var previewPlayer = PreviewPlayer()
    PreviewPlayerView(previewPlayer: previewPlayer, hasProjectAssets: true)
}
