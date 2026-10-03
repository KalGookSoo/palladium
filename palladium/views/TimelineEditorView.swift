import CoreMedia
import SwiftUI

enum TimelineMetrics {
    static let rulerHeight = 24.0
    static let trackHeight = 44.0
    static let clipVerticalInset = 4.0
    static let trackHeaderWidth = 80.0
    /// 시퀀스 끝 뒤에 남겨 두는 여백. 끝 근처 클립도 스크롤 없이 끝까지 보이게 한다.
    static let trailingPaddingSeconds = 30.0
}

/// SwiftUI의 `TimelineView`(일정 주기로 다시 그리는 View)와 이름이 겹치지 않도록 `TimelineEditorView`로 짓는다.
/// `VSplitView` 안에서는 다시 만들어질 때 `@State`를 잃으므로 선택·재생 헤드·배율은 상위(`MainWindowView`)가 소유한다.
struct TimelineEditorView: View {
    let sequence: EditSequence
    let assets: [MediaAsset]
    @Binding var selectedClipID: Clip.ID?
    @Binding var playheadTime: CMTime
    @Binding var scale: TimelineScale
    @State private var pinchStartScale: TimelineScale?

    var body: some View {
        let paddedDuration = sequence.duration + CMTime(seconds: TimelineMetrics.trailingPaddingSeconds, preferredTimescale: standardTimescale)
        let contentWidth = scale.width(for: paddedDuration)
        let pinch = MagnifyGesture()
            .onChanged { value in
                let startScale = pinchStartScale ?? scale
                pinchStartScale = startScale
                scale = startScale.zoomed(byMagnification: value.magnification)
            }
            .onEnded { _ in pinchStartScale = nil }

        VStack(spacing: 0) {
            HStack {
                Text(sequence.name)
                    .font(.headline)
                Spacer()
                Button {
                    scale = scale.zoomedOut
                } label: {
                    Label("축소", systemImage: "minus.magnifyingglass")
                }
                .disabled(!scale.canZoomOut)
                .help("타임라인 축소 (⌘-)")

                Button {
                    scale = scale.zoomedIn
                } label: {
                    Label("확대", systemImage: "plus.magnifyingglass")
                }
                .disabled(!scale.canZoomIn)
                .help("타임라인 확대 (⌘=)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if sequence.tracks.allSatisfy(\.clips.isEmpty) {
                // 빈 타임라인은 "무엇을 하면 되는지"를 안내한다. 원본이 없으면 가져오기부터 안내한다.
                if assets.isEmpty {
                    ContentUnavailableView(
                        "타임라인이 비어 있음",
                        systemImage: "square.and.arrow.down",
                        description: Text("⌘I로 미디어를 가져온 뒤 타임라인에 배치하세요")
                    )
                } else {
                    ContentUnavailableView(
                        "타임라인이 비어 있음",
                        systemImage: "film.stack",
                        description: Text("미디어 패널에서 원본을 끌어다 놓아 클립을 추가하세요")
                    )
                }
            } else {
                timelineContent(contentWidth: contentWidth)
            }
        }
        .simultaneousGesture(pinch)
    }

    private func timelineContent(contentWidth: Double) -> some View {
        HStack(alignment: .top, spacing: 0) {
            TrackHeaderColumn(tracks: sequence.tracks)
            Divider()
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    TimelineRulerView(
                        scale: scale,
                        sequenceDuration: sequence.duration,
                        markers: sequence.markers,
                        playheadTime: $playheadTime
                    )
                    ForEach(sequence.tracks) { track in
                        TrackRowView(track: track, assets: assets, scale: scale, selectedClipID: $selectedClipID)
                    }
                }
                // 내용이 패널 높이를 채워야 가로 스크롤바가 마지막 트랙 위가 아니라 패널 바닥에 놓인다.
                .frame(width: contentWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .topLeading) {
                    PlayheadView()
                        .offset(x: scale.x(for: playheadTime) - 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct TrackHeaderColumn: View {
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: TimelineMetrics.rulerHeight)
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                // 같은 종류 트랙끼리 1부터 번호를 매긴다(예: 영상 1, 오디오 1).
                let number = tracks[...index].filter { $0.kind == track.kind }.count

                Label("\(track.kind.title) \(number)", systemImage: track.kind.symbolName)
                    .font(.caption)
                    .frame(height: TimelineMetrics.trackHeight)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: TimelineMetrics.trackHeaderWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview("빈 타임라인 — 원본 있음") {
    @Previewable @State var selectedClipID: Clip.ID?
    @Previewable @State var playheadTime = CMTime.zero
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: EditSequence(id: UUID(), name: "시퀀스 1", tracks: []),
        assets: SampleData.project.assets,
        selectedClipID: $selectedClipID,
        playheadTime: $playheadTime,
        scale: $scale
    )
    .frame(width: 700, height: 240)
}

#Preview("빈 타임라인 — 원본 없음") {
    @Previewable @State var selectedClipID: Clip.ID?
    @Previewable @State var playheadTime = CMTime.zero
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: EditSequence(id: UUID(), name: "시퀀스 1", tracks: []),
        assets: [],
        selectedClipID: $selectedClipID,
        playheadTime: $playheadTime,
        scale: $scale
    )
    .frame(width: 700, height: 240)
}

#Preview("샘플 시퀀스") {
    @Previewable @State var selectedClipID: Clip.ID?
    @Previewable @State var playheadTime = CMTime(seconds: 5, preferredTimescale: standardTimescale)
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: SampleData.mainSequence,
        assets: SampleData.project.assets,
        selectedClipID: $selectedClipID,
        playheadTime: $playheadTime,
        scale: $scale
    )
    .frame(width: 700, height: 240)
}
