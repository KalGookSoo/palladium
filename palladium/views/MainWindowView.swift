import CoreMedia
import SwiftUI

struct MainWindowView: View {
    @State private var isTimelineVisible = true
    @State private var isInspectorPresented = true
    @State private var aspectRatio: AspectRatioPreset = .landscape16x9
    @State private var project = SampleData.project
    /// 프리미어 프로처럼 미디어 패널 선택, 미리보기에 연 원본, 타임라인 클립 선택은 서로 독립이다.
    @State private var selectedAssetID: MediaAsset.ID?
    @State private var openedAssetID: MediaAsset.ID?
    @State private var selectedClipID: Clip.ID?
    @State private var playheadTime: CMTime = .zero
    @State private var timelineScale = TimelineScale(pointsPerSecond: 40)
    @State private var previewPlayer = PreviewPlayer()

    var body: some View {
        let openedAsset = project.assets.first { $0.id == openedAssetID }
        let currentSequence = project.sequences.first
        let selectedClip = currentSequence?.tracks.flatMap(\.clips).first { $0.id == selectedClipID }
        let selectedClipAsset = project.assets.first { $0.id == selectedClip?.assetID }

        NavigationSplitView {
            MediaPanelView(project: project, selectedAssetID: $selectedAssetID) { assetID in
                openedAssetID = assetID
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VSplitView {
                PreviewPlayerView(asset: openedAsset, previewPlayer: previewPlayer)
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                if isTimelineVisible, let currentSequence {
                    TimelineEditorView(
                        sequence: currentSequence,
                        assets: project.assets,
                        selectedClipID: $selectedClipID,
                        playheadTime: $playheadTime,
                        scale: $timelineScale
                    )
                    .frame(maxWidth: .infinity, minHeight: 160, idealHeight: 240, maxHeight: .infinity)
                }
            }
            // 창이 좁아질 때 양쪽 패널 대신 가운데가 먼저 줄어들도록 최소 폭을 명시한다.
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(clip: selectedClip, asset: selectedClipAsset)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
        .toolbar {
            MainWindowToolbar(
                aspectRatio: $aspectRatio,
                isTimelineVisible: $isTimelineVisible,
                isInspectorPresented: $isInspectorPresented
            )
        }
        .focusedSceneValue(\.isTimelineVisible, $isTimelineVisible)
        .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
        .focusedSceneValue(\.timelineScale, $timelineScale)
        .task(id: openedAssetID) {
            await previewPlayer.load(url: openedAsset?.sourceURL)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    MainWindowView()
}
