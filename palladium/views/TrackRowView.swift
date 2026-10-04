import AppKit
import CoreMedia
import SwiftUI

struct TrackRowView: View {
    let track: Track
    let assets: [MediaAsset]
    let scale: TimelineScale
    @Binding var selectedClipIDs: Set<Clip.ID>
    let actions: TimelineActions
    /// 클립을 끌어 놓았을 때 끈 거리와 함께 부른다. 시각·트랙 계산은 상위가 한다.
    let moveClip: (Clip, CGSize) -> Void
    /// 끄는 중인 클립과 끈 거리. 놓기 전까지 클립을 그만큼 옮겨 보여준다.
    @State private var dragging: (clipID: Clip.ID, translation: CGSize)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 빈 영역을 누르면 선택을 해제한다.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selectedClipIDs = [] }

            ForEach(track.clips) { clip in
                let asset = assets.first { $0.id == clip.assetID }
                let translation = dragging?.clipID == clip.id ? dragging?.translation ?? .zero : .zero
                let width = scale.width(for: clip.sourceRange.duration)

                ClipView(title: asset?.name ?? "알 수 없는 원본", symbolName: track.kind.symbolName, isSelected: selectedClipIDs.contains(clip.id)) {
                    ClipContentView(asset: asset, clip: clip, width: width)
                }
                .frame(
                    width: width,
                    height: TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
                )
                .offset(x: scale.x(for: clip.timelineStart) + translation.width, y: TimelineMetrics.clipVerticalInset + translation.height)
                .zIndex(dragging?.clipID == clip.id ? 1 : 0)
                .onTapGesture { select(clip) }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in dragging = (clip.id, value.translation) }
                        .onEnded { value in
                            dragging = nil
                            moveClip(clip, value.translation)
                        }
                )
                .contextMenu { clipMenu(for: clip) }
            }
        }
        .frame(height: TimelineMetrics.trackHeight)
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

        // 메뉴 오른쪽에 단축키를 보여준다. 실제 단축키는 편집 창의 키 입력 처리(EditorKeyMonitor)가 맡는다.
        Button(ShortcutGuide.deleteClips.title) { actions.deleteClips(targetIDs, false) }
            .keyboardShortcut(.delete, modifiers: [])
        Button(ShortcutGuide.rippleDeleteClips.title) { actions.deleteClips(targetIDs, true) }
            .keyboardShortcut(.delete, modifiers: .shift)
        Button(ShortcutGuide.splitAtPlayhead.title) { actions.splitClips(targetIDs) }
            .keyboardShortcut("b", modifiers: .command)
        Divider()
        Button("미리보기에서 원본 열기") { actions.openAsset(clip.assetID) }
        Button("미디어 패널에서 원본 보기") { actions.revealAsset(clip.assetID) }
    }
}
