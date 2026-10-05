import CoreMedia
import SwiftUI

/// 레인 위의 블록 하나(자막 하나, 마스크 하나).
struct RangeLaneItem: Identifiable {
    let id: UUID
    let range: CMTimeRange
    let title: String
}

/// 눈금자 아래 자막(#4)·마스크(#59) 레인. 블록을 눌러 고르고, 끌어서 옮기고, 양 끝을 끌어 시작·끝을 바꾼다.
/// 결과물 시간에 붙으므로 클립을 옮겨도 따라가지 않는다.
struct RangeLaneView: View {
    let items: [RangeLaneItem]
    let tint: Color
    /// 끌 때 붙을 클립 경계를 찾는 데 쓴다.
    let sequence: EditSequence
    let scale: TimelineScale
    let playheadTime: CMTime
    @Binding var selectedID: UUID?
    let addTitle: String
    let deleteTitle: String
    let helpText: String
    let add: () -> Void
    let setRange: (UUID, CMTime, CMTime) -> Void
    let delete: (UUID) -> Void
    /// 자막·마스크의 최소 길이와 같다. 편집기도 같은 값으로 맞춘다.
    private static let minimumDuration = CMTime(value: 1, timescale: 10)
    /// 끄는 중인 블록과 끄는 동안의 구간. 손을 떼면 편집기에 반영한다.
    @State private var dragging: (id: UUID, range: CMTimeRange)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: add)
                .onTapGesture { selectedID = nil }
                .contextMenu {
                    Button(addTitle, action: add)
                }

            ForEach(items) { item in
                block(for: item)
            }
        }
        .frame(height: TimelineMetrics.rangeLaneHeight)
        .background(.quaternary.opacity(0.4))
        .help(helpText)
    }

    private var blockHeight: Double {
        TimelineMetrics.rangeLaneHeight - 6
    }

    private func block(for item: RangeLaneItem) -> some View {
        let range = dragging?.id == item.id ? dragging?.range ?? item.range : item.range
        let width = max(scale.width(for: range.duration) - 2, 4)
        let isSelected = selectedID == item.id
        let handleWidth = min(6, width / 3)

        return Text(item.title)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: width, height: blockHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(isSelected ? 0.55 : 0.3)))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : tint, lineWidth: isSelected ? 2 : 1)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { selectedID = item.id }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in preview(item, edge: nil, distance: value.translation.width) }
                    .onEnded { value in commit(item, edge: nil, distance: value.translation.width) }
            )
            .overlay(alignment: .leading) { edgeHandle(item, edge: .start, width: handleWidth) }
            .overlay(alignment: .trailing) { edgeHandle(item, edge: .end, width: handleWidth) }
            .contextMenu {
                Button(deleteTitle) { delete(item.id) }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .offset(x: scale.x(for: range.start) + 1, y: 3)
    }

    private func edgeHandle(_ item: RangeLaneItem, edge: ClipEdge, width: Double) -> some View {
        Color.clear
            .frame(width: width, height: blockHeight)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in preview(item, edge: edge, distance: value.translation.width) }
                    .onEnded { value in commit(item, edge: edge, distance: value.translation.width) }
            )
            .help("끌어서 시작·끝 시각을 바꿉니다")
    }

    // MARK: - Drag

    /// 끈 거리만큼 옮긴(`edge`가 `nil`) 또는 한쪽 끝을 바꾼 구간. 클립 경계·재생 헤드에 10pt 안이면 붙는다.
    private func movedRange(_ item: RangeLaneItem, edge: ClipEdge?, distance: Double) -> CMTimeRange {
        let range = item.range
        let tolerance = scale.time(forX: 10)
        let shifted = { (time: CMTime) in scale.time(forX: scale.x(for: time) + distance) }
        switch edge {
        case nil:
            let start = sequence.snappedStart(shifted(range.start), duration: range.duration, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: start, duration: range.duration)
        case .start:
            let start = sequence.snappedStart(shifted(range.start), duration: .zero, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: CMTimeMinimum(start, range.end - Self.minimumDuration), end: range.end)
        case .end:
            let end = sequence.snappedStart(shifted(range.end), duration: .zero, tolerance: tolerance, extraEdges: [playheadTime])
            return CMTimeRange(start: range.start, end: CMTimeMaximum(end, range.start + Self.minimumDuration))
        }
    }

    private func preview(_ item: RangeLaneItem, edge: ClipEdge?, distance: Double) {
        selectedID = item.id
        dragging = (item.id, movedRange(item, edge: edge, distance: distance))
    }

    private func commit(_ item: RangeLaneItem, edge: ClipEdge?, distance: Double) {
        let range = movedRange(item, edge: edge, distance: distance)
        dragging = nil
        setRange(item.id, range.start, range.end)
    }
}
