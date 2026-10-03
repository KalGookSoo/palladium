import CoreMedia
import OSLog
import SwiftData
import SwiftUI

/// 사이드바와 인스펙터만 폭 범위를 가진다. 가운데 영역과 창에는 최소 폭을 두지 않는다 —
/// 최소 폭끼리 동시에 만족될 수 없으면 분할 뷰 제약이 끝없이 다시 계산되다 앱이 중단되기 때문이다(#32).
/// 창이 좁아지면 가운데 영역이 먼저 줄어들고, 넘치는 내용은 잘려 보인다.
enum MainWindowMetrics {
    static let sidebarMinWidth = 200.0
    static let sidebarIdealWidth = 240.0
    static let sidebarMaxWidth = 320.0
    static let inspectorMinWidth = 240.0
    static let inspectorIdealWidth = 280.0
    static let inspectorMaxWidth = 320.0
}

struct MainWindowView: View {
    @State private var isTimelineVisible = true
    @State private var isInspectorPresented = true
    @State private var aspectRatio: AspectRatioPreset = .landscape16x9
    @State private var project: Project
    /// 마지막으로 저장한 내용. 지금 프로젝트와 다르면 저장하지 않은 변경이 있다.
    @State private var savedProject: Project
    @State private var saveErrorMessage: String?
    @Environment(\.modelContext) private var modelContext
    /// 프리미어 프로처럼 미디어 패널 선택, 미리보기에 연 원본, 타임라인 클립 선택은 서로 독립이다.
    @State private var selectedAssetID: MediaAsset.ID?
    @State private var openedAssetID: MediaAsset.ID?
    @State private var selectedClipID: Clip.ID?
    @State private var playheadTime: CMTime = .zero
    @State private var timelineScale = TimelineScale(pointsPerSecond: 40)
    @State private var previewPlayer = PreviewPlayer()

    init(project: Project) {
        _project = State(initialValue: project)
        _savedProject = State(initialValue: project)
    }

    var body: some View {
        let hasUnsavedChanges = project != savedProject
        // 저장할 변경이 없으면 nil을 넘겨 파일 > 저장 메뉴를 비활성화한다.
        let saveAction: (() -> Void)? = hasUnsavedChanges ? { _ = saveProject() } : nil
        let isShowingSaveError = Binding<Bool>(
            get: { saveErrorMessage != nil },
            set: {
                if !$0 {
                    saveErrorMessage = nil
                }
            }
        )
        let openedAsset = project.assets.first { $0.id == openedAssetID }
        let currentSequence = project.sequences.first
        let selectedClip = currentSequence?.tracks.flatMap(\.clips).first { $0.id == selectedClipID }
        let selectedClipAsset = project.assets.first { $0.id == selectedClip?.assetID }

        NavigationSplitView {
            MediaPanelView(project: project, selectedAssetID: $selectedAssetID) { assetID in
                openedAssetID = assetID
            }
            .navigationSplitViewColumnWidth(
                min: MainWindowMetrics.sidebarMinWidth,
                ideal: MainWindowMetrics.sidebarIdealWidth,
                max: MainWindowMetrics.sidebarMaxWidth
            )
        } detail: {
            VSplitView {
                PreviewPlayerView(asset: openedAsset, previewPlayer: previewPlayer, hasProjectAssets: !project.assets.isEmpty)
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
            // 가운데 영역은 0까지 줄어들 수 있게 해 양쪽 패널 폭을 먼저 지키고, 넘치는 내용은 잘라낸다.
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(clip: selectedClip, asset: selectedClipAsset)
                .inspectorColumnWidth(
                    min: MainWindowMetrics.inspectorMinWidth,
                    ideal: MainWindowMetrics.inspectorIdealWidth,
                    max: MainWindowMetrics.inspectorMaxWidth
                )
        }
        .toolbar {
            MainWindowToolbar(
                aspectRatio: $aspectRatio,
                isTimelineVisible: $isTimelineVisible,
                isInspectorPresented: $isInspectorPresented
            )
        }
        .focusedSceneValue(\.saveProject, saveAction)
        .focusedSceneValue(\.isTimelineVisible, $isTimelineVisible)
        .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
        .focusedSceneValue(\.timelineScale, $timelineScale)
        .task(id: openedAssetID) {
            await previewPlayer.load(url: openedAsset?.sourceURL)
        }
        .frame(minHeight: 600)
        .navigationTitle(project.name)
        .background {
            UnsavedChangesGuard(hasUnsavedChanges: hasUnsavedChanges, projectName: project.name, save: saveProject)
        }
        .alert("저장하지 못했습니다", isPresented: isShowingSaveError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        // 디버그 메뉴에서 이름 끝에 표시를 붙여 저장하지 않은 변경 상태를 만든다.
        #if DEBUG
        .focusedSceneValue(\.makeUnsavedChange) { project.name += " ✎" }
        #endif
    }

    /// 저장에 성공하면 `true`. 닫기·종료 확인 창은 실패하면 창을 닫지 않는다.
    private func saveProject() -> Bool {
        do {
            try SwiftDataProjectRepository(modelContext: modelContext).save(project)
            savedProject = project
            return true
        } catch {
            Logger.project.error("프로젝트 저장 실패: \(error.localizedDescription, privacy: .public)")
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}

#Preview {
    MainWindowView(project: SampleData.project)
}
