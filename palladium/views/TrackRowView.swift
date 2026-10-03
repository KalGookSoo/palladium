import CoreMedia
import SwiftUI

struct TrackRowView: View {
    let track: Track
    let assets: [MediaAsset]
    let scale: TimelineScale
    @Binding var selectedClipID: Clip.ID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 빈 영역을 누르면 선택을 해제한다.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selectedClipID = nil }

            ForEach(track.clips) { clip in
                let assetName = assets.first { $0.id == clip.assetID }?.name ?? "알 수 없는 원본"

                ClipView(title: assetName, symbolName: track.kind.symbolName, isSelected: clip.id == selectedClipID)
                    .frame(
                        width: scale.width(for: clip.sourceRange.duration),
                        height: TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
                    )
                    .offset(x: scale.x(for: clip.timelineStart), y: TimelineMetrics.clipVerticalInset)
                    .onTapGesture { selectedClipID = clip.id }
            }
        }
        .frame(height: TimelineMetrics.trackHeight)
    }
}
