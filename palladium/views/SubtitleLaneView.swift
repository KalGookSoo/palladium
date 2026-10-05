import CoreMedia
import SwiftUI

/// 눈금자 바로 아래의 자막 트랙(#4). 자막을 눌러 고르고, 끌어서 옮기고, 양 끝을 끌어 시작·끝을 바꾼다.
/// 자막은 결과물 시간에 붙으므로 클립을 옮겨도 따라가지 않는다.
struct SubtitleLaneView: View {
    let sequence: EditSequence
    let scale: TimelineScale
    let playheadTime: CMTime
    @Binding var selectedSubtitleID: Subtitle.ID?
    let actions: TimelineActions
    /// 끄는 중인 자막과 끄는 동안의 구간. 손을 떼면 편집기에 반영한다.
    @State private var dragging: (id: Subtitle.ID, range: CMTimeRange)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { actions.addSubtitle() }
                .onTapGesture { selectedSubtitleID = nil }
                .contextMenu {
                    Button(ShortcutGuide.addSubtitle.title, action: actions.addSubtitle)
                }

            ForEach(sequence.subtitles) { subtitle in
                block(for: subtitle)
            }
        }
        .frame(height: TimelineMetrics.subtitleLaneHeight)
        .background(.quaternary.opacity(0.4))
        .help("자막 트랙 — 두 번 클릭하거나 우클릭해 재생 헤드에 자막을 추가합니다")
    }

    private var blockHeight: Double {
        TimelineMetrics.subtitleLaneHeight - 6
    }

    private func block(for subtitle: Subtitle) -> some View {
        let range = dragging?.id == subtitle.id ? dragging?.range ?? subtitle.range : subtitle.range
        let width = max(scale.width(for: range.duration) - 2, 4)
        let isSelected = selectedSubtitleID == subtitle.id
        let handleWidth = min(6, width / 3)

        return Text(subtitle.text.replacingOccurrences(of: "\n", with: " "))
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: width, height: blockHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(isSelected ? 0.55 : 0.3)))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.teal, lineWidth: isSelected ? 2 : 1)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { selectedSubtitleID = subtitle.id }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in preview(subtitle, edge: nil, distance: value.translation.width) }
                    .onEnded { value in commit(subtitle, edge: nil, distance: value.translation.width) }
            )
            .overlay(alignment: .leading) { edgeHandle(subtitle, edge: .start, width: handleWidth) }
            .overlay(alignment: .trailing) { edgeHandle(subtitle, edge: .end, width: handleWidth) }
            .contextMenu {
                Button("자막 삭제") { actions.deleteSubtitle(subtitle.id) }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .offset(x: scale.x(for: range.start) + 1, y: 3)
    }

    private func edgeHandle(_ subtitle: Subtitle, edge: ClipEdge, width: Double) -> some View {
        Color.clear
            .frame(width: width, height: blockHeight)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in preview(subtitle, edge: edge, distance: value.translation.width) }
                    .onEnded { value in commit(subtitle, edge: edge, distance: value.translation.width) }
            )
            .help("끌어서 자막이 나오는 시작·끝 시각을 바꿉니다")
    }

    // MARK: - Drag

    /// 끈 거리만큼 옮긴(`edge`가 `nil`) 또는 한쪽 끝을 바꾼 구간. 클립 경계·재생 헤드에 10pt 안이면 붙는다.
    private func movedRange(_ subtitle: Subtitle, edge: ClipEdge?, distance: Double) -> CMTimeRange {
        let range = subtitle.range
        let tolerance = scale.time(forX: 10)
        let shifted = { (time: CMTime) in scale.time(forX: scale.x(for: time) + distance) }
        switch edge {
        case nil:
            let start = sequence.snappedStart(shifted(range.start), duration: range.duration, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: start, duration: range.duration)
        case .start:
            let start = sequence.snappedStart(shifted(range.start), duration: .zero, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: CMTimeMinimum(start, range.end - Subtitle.minimumDuration), end: range.end)
        case .end:
            let end = sequence.snappedStart(shifted(range.end), duration: .zero, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: range.start, end: CMTimeMaximum(end, range.start + Subtitle.minimumDuration))
        }
    }

    private func preview(_ subtitle: Subtitle, edge: ClipEdge?, distance: Double) {
        selectedSubtitleID = subtitle.id
        dragging = (subtitle.id, movedRange(subtitle, edge: edge, distance: distance))
    }

    private func commit(_ subtitle: Subtitle, edge: ClipEdge?, distance: Double) {
        let range = movedRange(subtitle, edge: edge, distance: distance)
        dragging = nil
        actions.setSubtitleRange(subtitle.id, range.start, range.end)
    }
}
