import AVFoundation
import CoreMedia
import Observation
import SwiftUI

/// 다듬기 시트를 열 대상(#81). 미디어 패널에서 열면 원본 항목, 타임라인에서 열면 클립 하나를 바꾼다.
struct TrimTarget: Identifiable {
    enum Kind: Equatable {
        case asset(MediaAsset.ID)
        case clip(Clip.ID)
    }

    let id = UUID()
    let kind: Kind
}

/// QuickTime의 다듬기처럼 영상·오디오 하나를 원본 전체와 함께 보며 구간을 고르고 나눈다(#81).
/// 미리보기의 굳은 결정("시퀀스만 재생")의 예외로, 이 시트에서만 원본 구간을 재생한다. 원본 파일은 바꾸지 않는다.
/// 고르는 동안은 시트 안에서만 바뀌고, "다듬기"(원본은 "이 원본에 적용"·"새 원본으로 추가")나 "여기서 분할"을 눌러야 프로젝트가 바뀐다.
struct TrimSheetView: View {
    let editor: ProjectEditor
    @State private var kind: TrimTarget.Kind
    @State private var range: CMTimeRange
    /// 방향키가 옮기는 손잡이. 마지막으로 잡은 쪽이다.
    @State private var activeEdge = ClipEdge.end
    @State private var player: TrimPlayer?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    /// 시간 글자(분:초.소수 첫째 자리)를 만드는 데만 쓴다.
    private let labelScale = TimelineScale(pointsPerSecond: 40)

    init(editor: ProjectEditor, target: TrimTarget) {
        self.editor = editor
        _kind = State(initialValue: target.kind)
        _range = State(initialValue: Self.currentRange(of: target.kind, in: editor) ?? CMTimeRange(start: .zero, duration: .zero))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset {
                Text("다듬기 — \(title(for: asset))")
                    .font(.headline)
                    .lineLimit(1)
                picture(for: asset)
                HStack(spacing: 12) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                            .frame(width: 20)
                    }
                    .help("고른 구간 재생/일시정지 (Space)")
                    TrimBarView(
                        asset: asset,
                        range: range,
                        playhead: player?.currentTime ?? range.start,
                        activeEdge: activeEdge,
                        moveEdge: moveEdge,
                        scrub: { player?.seek(to: $0) }
                    )
                }
                timeSummary
                actions(for: asset)
            } else {
                ContentUnavailableView("다듬을 대상이 없습니다", systemImage: "scissors", description: Text("원본이나 클립이 지워졌습니다"))
                Button("닫기") { dismiss() }
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 540)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .space]) { press in
            handle(press)
        }
        .task(id: asset?.mediaKey) {
            guard let asset else { return }
            player = TrimPlayer(url: ProxyGenerator.previewURL(for: asset))
            player?.seek(to: range.start)
            isFocused = true
        }
        .onDisappear { player?.stop() }
    }

    // MARK: - Parts

    private func picture(for asset: MediaAsset) -> some View {
        Group {
            if asset.kind == .video, let player {
                PlayerSurfaceView(player: player.player)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var timeSummary: some View {
        HStack {
            Text("시작 \(labelScale.timeLabel(for: range.start)) · 끝 \(labelScale.timeLabel(for: range.end)) · 길이 \(labelScale.timeLabel(for: range.duration))")
                .monospacedDigit()
            Spacer()
            Text("↑/↓ \(activeEdge == .start ? "시작" : "끝")을 0.1초씩, ⇧와 함께 1초씩")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func actions(for asset: MediaAsset) -> some View {
        let playhead = player?.currentTime ?? range.start
        HStack {
            Button("여기서 분할") { split(at: playhead) }
                .disabled(!TrimRange.canSplit(range, at: playhead))
                .help("재생 위치에서 둘로 나눕니다. 옮겨 둔 손잡이 구간도 함께 반영합니다")
            Spacer()
            Button("취소", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            switch kind {
            case .asset:
                Button("새 원본으로 추가") {
                    editor.addTrimmedAsset(from: asset.id, start: range.start, end: range.end)
                    dismiss()
                }
                .help("같은 파일을 가리키는 새 항목을 이 구간으로 미디어 패널에 추가합니다(파일은 복사하지 않음)")
                Button("이 원본에 적용") {
                    editor.setUsedRange(start: range.start, end: range.end, for: asset.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help("타임라인에 놓으면 이 구간만 들어갑니다. 원본 파일은 그대로입니다")
            case let .clip(clipID):
                Button("다듬기") {
                    editor.commitClipTrim(clipID, start: range.start, end: range.end)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Model

    private var asset: MediaAsset? {
        switch kind {
        case let .asset(assetID): editor.asset(id: assetID)
        case let .clip(clipID): editor.currentSequence.clip(id: clipID).flatMap { editor.asset(id: $0.assetID) }
        }
    }

    private func title(for asset: MediaAsset) -> String {
        guard case let .clip(clipID) = kind, let clip = editor.currentSequence.clip(id: clipID) else { return asset.name }
        return clip.displayName(assetName: asset.name)
    }

    /// 대상의 지금 구간. 원본은 사용 구간(없으면 전체), 클립은 쓰는 원본 구간이다.
    private static func currentRange(of kind: TrimTarget.Kind, in editor: ProjectEditor) -> CMTimeRange? {
        switch kind {
        case let .asset(assetID):
            return editor.asset(id: assetID).map { $0.usedRange ?? CMTimeRange(start: .zero, duration: $0.duration) }
        case let .clip(clipID):
            return editor.currentSequence.clip(id: clipID)?.sourceRange
        }
    }

    private func moveEdge(_ edge: ClipEdge, to time: CMTime) {
        guard let asset else { return }
        activeEdge = edge
        range = TrimRange.moving(range, edge: edge, to: time, sourceDuration: asset.duration)
        player?.seek(to: edge == .start ? range.start : range.end)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let asset else { return .ignored }
        switch press.key {
        case .space:
            togglePlayback()
        default:
            let step = press.modifiers.contains(.shift) ? TrimRange.largeStep : TrimRange.smallStep
            let delta = press.key == .upArrow ? step : CMTime.zero - step
            range = TrimRange.nudging(range, edge: activeEdge, by: delta, sourceDuration: asset.duration)
            player?.seek(to: activeEdge == .start ? range.start : range.end)
        }
        return .handled
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play(range)
        }
    }

    /// 옮겨 둔 구간을 함께 반영해 재생 위치에서 나누고, 앞 조각을 계속 다듬는다.
    private func split(at time: CMTime) {
        player?.pause()
        switch kind {
        case let .clip(clipID):
            guard editor.splitClip(clipID, start: range.start, end: range.end, at: time) else { return }
        case let .asset(assetID):
            guard let pieces = editor.splitAsset(assetID, start: range.start, end: range.end, at: time) else { return }
            kind = .asset(pieces.front)
        }
        if let current = Self.currentRange(of: kind, in: editor) {
            range = current
        }
    }
}

// MARK: - Bar

/// 원본 전체 필름스트립(오디오는 파형) 위에 고른 구간을 노란 테두리로, 바깥은 어둡게 보여준다.
/// 양 끝 손잡이를 끌어 구간을 바꾸고, 띠를 누르거나 끌어 재생 위치를 옮긴다.
private struct TrimBarView: View {
    let asset: MediaAsset
    let range: CMTimeRange
    let playhead: CMTime
    let activeEdge: ClipEdge
    let moveEdge: (ClipEdge, CMTime) -> Void
    let scrub: (CMTime) -> Void
    private static let height = TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
    private static let handleWidth = 12.0
    private static let space = "trimBar"

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (time: CMTime) in asset.duration.seconds > 0 ? time.seconds / asset.duration.seconds * width : 0 }
            let time = { (x: Double) in CMTime(seconds: min(max(x, 0), width) / max(width, 1) * asset.duration.seconds, preferredTimescale: standardTimescale) }
            let startX = x(range.start)
            let endX = x(range.end)

            ZStack(alignment: .topLeading) {
                content(width: width)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { scrub(time($0.location.x)) })
                // 고르지 않은 바깥은 어둡게.
                Color.black.opacity(0.55)
                    .frame(width: max(startX, 0))
                    .allowsHitTesting(false)
                Color.black.opacity(0.55)
                    .frame(width: max(width - endX, 0))
                    .offset(x: endX)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.yellow, lineWidth: 3)
                    .frame(width: max(endX - startX, 6))
                    .offset(x: startX)
                    .allowsHitTesting(false)
                handle(.start, x: startX, time: time)
                handle(.end, x: endX - Self.handleWidth, time: time)
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 1)
                    .offset(x: x(playhead) - 1)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: Self.height)
    }

    private func content(width: Double) -> some View {
        let fullClip = Clip(assetID: asset.id, sourceRange: CMTimeRange(start: .zero, duration: asset.duration), timelineStart: .zero)
        return Group {
            if let fullClip {
                ClipContentView(asset: asset, clip: fullClip, width: width, showsFilmstrip: true, showsWaveform: asset.kind == .audio)
            }
        }
        .frame(width: width, height: Self.height)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private func handle(_ edge: ClipEdge, x: Double, time: @escaping (Double) -> CMTime) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.yellow)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.5))
                    .frame(width: 2, height: Self.height / 2)
            }
            .overlay {
                // 방향키가 옮기는 쪽을 테두리로 알린다.
                if edge == activeEdge {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.5)
                }
            }
            .frame(width: Self.handleWidth, height: Self.height)
            .offset(x: x)
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { moveEdge(edge, time($0.location.x)) }
            )
            .help(edge == .start ? "시작 손잡이 — 끌어서 시작을 바꿉니다" : "끝 손잡이 — 끌어서 끝을 바꿉니다")
    }
}

// MARK: - Player

/// 다듬기 시트에서 원본을 재생하는 플레이어. 시퀀스 미리보기(`PreviewPlayer`)와 따로 둔다.
@Observable
final class TrimPlayer {
    let player = AVPlayer()
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    @ObservationIgnored private var timeObserver: Any?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time
                self?.isPlaying = self?.player.rate != 0
            }
        }
    }

    func seek(to time: CMTime) {
        currentTime = time
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 고른 구간만 재생하고 끝에서 멈춘다. 재생 위치가 구간 밖이거나 끝이면 처음부터.
    func play(_ range: CMTimeRange) {
        player.currentItem?.forwardPlaybackEndTime = range.end
        if currentTime < range.start || currentTime >= range.end - Clip.minimumDuration {
            seek(to: range.start)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
