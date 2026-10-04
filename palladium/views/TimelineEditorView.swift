import AppKit
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
/// 타임라인을 숨겼다 다시 보여도 유지되도록 선택·재생 헤드·배율은 상위(`MainWindowView`)가 소유한다.
struct TimelineEditorView: View {
    let sequence: EditSequence
    let assets: [MediaAsset]
    @Binding var selectedClipID: Clip.ID?
    @Binding var playheadTime: CMTime
    @Binding var scale: TimelineScale
    /// 미디어 패널에서 원본을 끌어다 놓았을 때 부른다. 트랙이 `nil`이면 트랙 밖(빈 곳)에 놓은 것이다.
    let dropAsset: (MediaAsset.ID, Track.ID?, CMTime, PlacementMode) -> Void
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
                .help(ShortcutGuide.zoomOutTimeline.helpText)

                Button {
                    scale = scale.zoomedIn
                } label: {
                    Label("확대", systemImage: "plus.magnifyingglass")
                }
                .disabled(!scale.canZoomIn)
                .help(ShortcutGuide.zoomInTimeline.helpText)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if sequence.tracks.allSatisfy(\.clips.isEmpty) {
                // 빈 타임라인은 "무엇을 하면 되는지"를 안내한다. 원본이 없으면 가져오기부터 안내한다.
                Group {
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
                }
                // 안내가 남은 높이를 채워야 헤더가 미리보기와의 경계 바로 아래에 붙는다.
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    handleDrop(items, trackID: nil, time: .zero)
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
                // 놓은 높이로 트랙을, 가로 위치로 시각을 정한다. 트랙 아래 빈 곳에 놓으면 새 트랙을 만든다.
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, location in
                    let trackIndex = Int(((location.y - TimelineMetrics.rulerHeight) / TimelineMetrics.trackHeight).rounded(.down))
                    let trackID = sequence.tracks.indices.contains(trackIndex) ? sequence.tracks[trackIndex].id : nil
                    // 10pt 안의 클립 경계나 0초에 붙여 클립 사이에 틈이 생기지 않게 한다.
                    let time = sequence.snappedTime(scale.time(forX: location.x), tolerance: scale.time(forX: 10))
                    return handleDrop(items, trackID: trackID, time: time)
                }
                .overlay(alignment: .topLeading) {
                    PlayheadView()
                        .offset(x: scale.x(for: playheadTime) - 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 미디어 패널은 원본 ID를 문자열로 끌어 보낸다. ⌘를 누른 채 놓으면 삽입, 아니면 덮어쓰기다.
    private func handleDrop(_ items: [String], trackID: Track.ID?, time: CMTime) -> Bool {
        let assetIDs = items.compactMap(UUID.init(uuidString:))
        guard let assetID = assetIDs.first else { return false }
        let mode: PlacementMode = NSEvent.modifierFlags.contains(.command) ? .insert : .overwrite
        dropAsset(assetID, trackID, time, mode)
        return true
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
        scale: $scale,
        dropAsset: { _, _, _, _ in }
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
        scale: $scale,
        dropAsset: { _, _, _, _ in }
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
        scale: $scale,
        dropAsset: { _, _, _, _ in }
    )
    .frame(width: 700, height: 240)
}
