import AppKit
import CoreMedia
import SwiftUI

struct TrackRowView: View {
    let track: Track
    let assets: [MediaAsset]
    let scale: TimelineScale
    let playheadTime: CMTime
    let showsFilmstrip: Bool
    let showsWaveform: Bool
    @Binding var selectedClipIDs: Set<Clip.ID>
    let actions: TimelineActions
    /// 이 행에서 끄는 중인 클립과 끈 거리. 포인터를 따라 반투명하게 그린다.
    let ghost: (clip: Clip, translation: CGSize)?
    /// 끄는 중인 클립·원본이 들어갈 자리. 강조 테두리와 삽입선으로 보여준다.
    let placeholder: Clip?
    /// 끄는 중이라 원래 자리에 보이지 않게 남겨 둔 클립(끌기 제스처를 이어 가기 위함).
    var hiddenClipID: Clip.ID?
    /// 트림 중이면 클립 안 내용을 다시 불러오지 않는다(#80).
    var freezesContent = false
    /// 끄는 동안과 놓았을 때 끈 거리와 함께 부른다. 시각·트랙 계산은 상위가 한다.
    let dragChanged: (Clip, CGSize) -> Void
    let dragEnded: (Clip, CGSize) -> Void
    /// 클립 끝을 끄는 동안과 놓았을 때 가로로 끈 거리와 함께 부른다(트림).
    let trimChanged: (Clip, ClipEdge, Double) -> Void
    let trimEnded: (Clip, ClipEdge, Double) -> Void
    /// 끌기 제스처가 끝나거나 끊길 때 부른다. 끊긴 끌기도 원래대로 돌리기 위함이다.
    var dragFinished: () -> Void = {}
    @GestureState private var isPointerDragging = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 빈 영역을 누르면 선택을 해제한다.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selectedClipIDs = [] }
                .contextMenu { pasteButton }

            ForEach(track.clips) { clip in
                clipView(clip, offset: .zero)
                    .overlay(alignment: .topLeading) { trimHandles(for: clip) }
                    .opacity(clip.id == hiddenClipID ? 0 : 1)
            }

            // 컷 지점을 가운데 둔 전환 구간. 영상 전환은 띠로, 오디오 크로스페이드는 아래쪽 막대로 보여준다.
            ForEach(track.clips.filter { $0.id != hiddenClipID }) { clip in
                transitionMarks(for: clip)
            }
            .allowsHitTesting(false)

            if let placeholder {
                PlaceholderView()
                    .frame(width: scale.width(for: placeholder.timelineDuration), height: clipHeight)
                    .offset(x: scale.x(for: placeholder.timelineStart), y: TimelineMetrics.clipVerticalInset)
                    .allowsHitTesting(false)
            }

            if let ghost {
                clipView(ghost.clip, offset: ghost.translation)
                    .opacity(0.6)
                    .zIndex(1)
            }
        }
        .frame(height: TimelineMetrics.trackHeight)
        .onChange(of: isPointerDragging) {
            if !isPointerDragging {
                dragFinished()
            }
        }
    }

    private var clipHeight: Double {
        TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
    }

    /// 맞닿은 클립 사이에 틈이 보이도록 양옆을 1pt씩 줄여 그린다.
    private func clipView(_ clip: Clip, offset: CGSize) -> some View {
        let asset = assets.first { $0.id == clip.assetID }
        let width = scale.width(for: clip.timelineDuration)

        let assetName = asset?.name ?? "알 수 없는 원본"
        // 별칭이 없으면 원본 이름이다. 속도를 바꾼 클립은 이름 뒤에 배율을 붙인다.
        let title = clip.displayName(assetName: assetName) + (clip.speed == 1 ? "" : " · \(clip.speed.formatted())×")

        return ClipView(
            title: title,
            symbolName: track.kind.symbolName,
            isSelected: selectedClipIDs.contains(clip.id),
            colorLabel: clip.colorLabel,
            hasEffect: !clip.colorAdjustment.isDefault
        ) {
            ClipContentView(asset: asset, clip: clip, width: width, showsFilmstrip: showsFilmstrip, showsWaveform: showsWaveform, isFrozen: freezesContent)
        }
        .help("원본: \(assetName)")
        .frame(width: max(width - 2, 1), height: clipHeight)
        .offset(x: scale.x(for: clip.timelineStart) + 1 + offset.width, y: TimelineMetrics.clipVerticalInset + offset.height)
        .onTapGesture { select(clip) }
        // 두 번 누르면 다듬기 시트를 연다(#81). 한 번 누르기 선택이 늦어지지 않게 함께 받는다.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if asset?.isTrimmable == true {
                actions.openTrimSheet(clip.id)
            }
        })
        .gesture(
            DragGesture(minimumDistance: 3)
                .updating($isPointerDragging) { _, isDragging, _ in isDragging = true }
                .onChanged { value in dragChanged(clip, value.translation) }
                .onEnded { value in dragEnded(clip, value.translation) }
        )
        .contextMenu { clipMenu(for: clip) }
    }

    @ViewBuilder
    private func transitionMarks(for clip: Clip) -> some View {
        let cut = scale.x(for: clip.timelineStart)
        if let transition = track.effectiveTransition(into: clip) {
            let width = scale.width(for: transition.duration)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.25))
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
                .overlay {
                    Image(systemName: transition.kind == .dissolve ? "circle.lefthalf.filled" : "rectangle.lefthalf.inset.filled")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: max(width, 6), height: clipHeight)
                .offset(x: cut - max(width, 6) / 2, y: TimelineMetrics.clipVerticalInset)
        }
        if let crossfade = track.effectiveAudioCrossfade(into: clip) {
            let width = max(scale.width(for: crossfade), 6)
            Capsule()
                .fill(Color.orange.opacity(0.8))
                .frame(width: width, height: 3)
                .offset(x: cut - width / 2, y: TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset - 4)
        }
    }

    /// 클립 양 끝의 잡는 영역. 끌면 그쪽 끝을 트림한다(클립 이동보다 먼저 받는다).
    private func trimHandles(for clip: Clip) -> some View {
        let width = scale.width(for: clip.timelineDuration)
        let handleWidth = min(6, width / 3)

        return ZStack(alignment: .topLeading) {
            trimHandle(clip, edge: .start, width: handleWidth)
                .offset(x: scale.x(for: clip.timelineStart))
            trimHandle(clip, edge: .end, width: handleWidth)
                .offset(x: scale.x(for: clip.timelineRange.end) - handleWidth)
        }
        .offset(y: TimelineMetrics.clipVerticalInset)
    }

    private func trimHandle(_ clip: Clip, edge: ClipEdge, width: Double) -> some View {
        Color.clear
            .frame(width: width, height: clipHeight)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($isPointerDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged { value in trimChanged(clip, edge, value.translation.width) }
                    .onEnded { value in trimEnded(clip, edge, value.translation.width) }
            )
            .help("끌어서 클립을 트림합니다. 뒤 클립이 따라오고, ⌥를 누르면 정밀하게, ⌘를 누르면 이웃 클립과의 경계를 옮깁니다(롤)")
    }

    /// ⌘ 클릭은 선택에 더하거나 빼고, ⇧ 클릭은 같은 트랙에서 이미 고른 클립과 이 클립 사이를 모두 고른다.
    private func select(_ clip: Clip) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedClipIDs.contains(clip.id) {
                selectedClipIDs.remove(clip.id)
            } else {
                selectedClipIDs.insert(clip.id)
            }
        } else if modifiers.contains(.shift), let anchor = track.clips.first(where: { selectedClipIDs.contains($0.id) }) {
            let lower = min(anchor.timelineStart, clip.timelineStart)
            let upper = max(anchor.timelineStart, clip.timelineStart)
            selectedClipIDs.formUnion(track.clips.filter { lower <= $0.timelineStart && $0.timelineStart <= upper }.map(\.id))
        } else {
            selectedClipIDs = [clip.id]
        }
    }

    /// 고른 클립 위에서 열면 고른 클립 모두에, 고르지 않은 클립 위에서 열면 그 클립에만 적용한다.
    @ViewBuilder
    private func clipMenu(for clip: Clip) -> some View {
        let targetIDs = selectedClipIDs.contains(clip.id) ? selectedClipIDs : [clip.id]
        let canSplit = targetIDs.contains { id in track.clips.first { $0.id == id }?.canSplit(at: playheadTime, clipIDs: nil) == true }

        // 메뉴 오른쪽에 단축키를 보여준다. 실제 단축키는 편집 창의 키 입력 처리와 편집 메뉴가 맡는다.
        Button(ShortcutGuide.deleteClips.title) { actions.deleteClips(targetIDs, false) }
            .keyboardShortcut(.delete, modifiers: [])
        Button(ShortcutGuide.rippleDeleteClips.title) { actions.deleteClips(targetIDs, true) }
            .keyboardShortcut(.delete, modifiers: .shift)
        // 재생 헤드가 클립 위에 없으면 나눌 곳이 없다.
        Button(ShortcutGuide.splitAtPlayhead.title) { actions.splitClips(targetIDs) }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!canSplit)
        // 앞 클립과 맞닿은 클립 하나에만 전환을 둔다. 길이는 기본 1초이고 인스펙터 전환 탭에서 바꾼다.
        if targetIDs.count == 1, track.kind == .video, track.maximumTransitionDuration(into: clip) >= ClipTransition.minimumDuration {
            Menu("앞 클립과 전환") {
                Button("디졸브") { actions.setTransition(clip.id, ClipTransition(kind: .dissolve, duration: clip.transitionIn?.duration ?? ClipTransition.defaultDuration)) }
                Button("와이프") { actions.setTransition(clip.id, ClipTransition(kind: .wipe, duration: clip.transitionIn?.duration ?? ClipTransition.defaultDuration)) }
                Divider()
                Button("전환 없음") { actions.setTransition(clip.id, nil) }
                    .disabled(clip.transitionIn == nil)
            }
        }
        Divider()
        Button(ShortcutGuide.cutClips.title) { actions.cutClips(targetIDs) }
            .keyboardShortcut("x", modifiers: .command)
        Button(ShortcutGuide.copyClips.title) { actions.copyClips(targetIDs) }
            .keyboardShortcut("c", modifiers: .command)
        pasteButton
        Button(ShortcutGuide.duplicateClips.title) { actions.duplicateClips(targetIDs) }
            .keyboardShortcut("d", modifiers: .command)
        Divider()
        // 다듬기(#81)는 영상·오디오 클립 하나만 연다.
        if targetIDs.count == 1, assets.first(where: { $0.id == clip.assetID })?.isTrimmable == true {
            Button(ShortcutGuide.trimSheet.title) { actions.openTrimSheet(clip.id) }
                .keyboardShortcut("t", modifiers: .command)
        }
        // 별칭은 클립마다 다르므로 하나를 골랐을 때만 바꾼다. 입력은 인스펙터 맨 위 이름 칸에서 한다.
        if targetIDs.count == 1 {
            Button(ShortcutGuide.rename.title) { actions.renameClip(clip.id) }
                .keyboardShortcut(.f2, modifiers: [])
        }
        Menu("색상 레이블") {
            Button("없음") { actions.setClipColorLabel(targetIDs, nil) }
            Divider()
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Button {
                    actions.setClipColorLabel(targetIDs, label)
                } label: {
                    Label(label.title, systemImage: "circle.fill")
                        .tint(label.color)
                }
            }
        }
        Divider()
        Button("원본 훑어보기") { actions.openAsset(clip.assetID) }
        Button("미디어 패널에서 원본 보기") { actions.revealAsset(clip.assetID) }
    }
}

private extension TrackRowView {
    /// 재생 헤드에 붙인다(마우스 위치가 아니다).
    var pasteButton: some View {
        Button(ShortcutGuide.pasteClips.title) { actions.paste?() }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(actions.paste == nil)
    }
}

/// 끄는 클립·원본이 들어갈 자리. 앞쪽 끝에 삽입선을 함께 그린다.
private struct PlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ClipViewMetrics.cornerRadius)
            .fill(Color.accentColor.opacity(0.15))
            .overlay {
                RoundedRectangle(cornerRadius: ClipViewMetrics.cornerRadius)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .padding(.vertical, -TimelineMetrics.clipVerticalInset)
            }
    }
}
