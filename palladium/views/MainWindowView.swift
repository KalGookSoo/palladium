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
    /// 열린 프로젝트와 편집 동작. 이 View는 화면 상태만 갖고 편집은 모두 편집기 커맨드로 한다.
    let editor: ProjectEditor
    @State private var saveErrorMessage: String?
    @State private var isImporterPresented = false
    @State private var importReport: MediaImportReport?
    /// 프리미어 프로처럼 미디어 패널 선택, 미리보기에 연 원본, 타임라인 클립 선택은 서로 독립이다.
    @State private var selectedAssetID: MediaAsset.ID?
    @State private var openedAssetID: MediaAsset.ID?
    @State private var selectedClipID: Clip.ID?
    @State private var playheadTime: CMTime = .zero
    @State private var timelineScale = TimelineScale(pointsPerSecond: 40)
    @State private var previewPlayer = PreviewPlayer()

    var body: some View {
        let project = editor.project
        let hasUnsavedChanges = editor.hasUnsavedChanges
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
        let isShowingImportReport = Binding<Bool>(
            get: { importReport != nil },
            set: {
                if !$0 {
                    importReport = nil
                }
            }
        )
        let openedAsset = project.assets.first { $0.id == openedAssetID }
        let currentSequence = project.sequences.first
        let selectedClip = currentSequence?.tracks.flatMap(\.clips).first { $0.id == selectedClipID }
        let selectedClipAsset = project.assets.first { $0.id == selectedClip?.assetID }

        NavigationSplitView {
            MediaPanelView(editor: editor, selectedAssetID: $selectedAssetID) { assetID in
                openedAssetID = assetID
            }
            // 놓을 곳을 창 전체로 잡으면 분할 뷰 경계를 덮어 크기 조절 커서가 나타나지 않으므로,
            // Finder에서 끌어온 파일은 미디어 패널과 미리보기에 놓을 때만 가져온다.
            .dropDestination(for: URL.self) { urls, _ in
                importMedia(from: urls)
                return true
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
                    .dropDestination(for: URL.self) { urls, _ in
                        importMedia(from: urls)
                        return true
                    }
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
                isInspectorPresented: $isInspectorPresented,
                importMedia: { isImporterPresented = true }
            )
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                importMedia(from: urls)
            case let .failure(error):
                Logger.mediaImport.error("파일 선택 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        .focusedSceneValue(\.saveProject, saveAction)
        .focusedSceneValue(\.importMedia) { isImporterPresented = true }
        .focusedSceneValue(\.isTimelineVisible, $isTimelineVisible)
        .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
        .focusedSceneValue(\.timelineScale, $timelineScale)
        .task { await writeBackupsPeriodically() }
        .modifier(PlaybackKeyHandling(handle: handlePlaybackKey))
        .task(id: openedAssetID) {
            await previewPlayer.load(url: openedAsset.map(MediaFileAccess.resolvedURL))
        }
        .frame(minHeight: 600)
        .navigationTitle(project.name)
        .background {
            UnsavedChangesGuard(
                hasUnsavedChanges: hasUnsavedChanges,
                projectName: project.name,
                save: saveProject,
                discardChanges: editor.discardBackup
            )
        }
        .alert(importReport?.summary?.title ?? "", isPresented: isShowingImportReport) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(importReport?.summary?.message ?? "")
        }
        .alert("저장하지 못했습니다", isPresented: isShowingSaveError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        #if DEBUG
        .debugCommandValues(editor: editor)
        #endif
    }

    /// 가져온 원본은 "분류 안 됨"에 추가되고 저장하지 않은 변경이 된다. 마지막으로 가져온(또는 이미 있던) 원본을 선택한다.
    private func importMedia(from urls: [URL]) {
        Task {
            let report = await editor.importMedia(from: urls)
            if let lastAssetID = report.imported.last?.id ?? report.duplicateIDs.last {
                selectedAssetID = lastAssetID
            }
            if report.summary != nil {
                importReport = report
            }
        }
    }

    /// 미리보기에 원본이 열려 있을 때만 키를 처리한다. 열린 원본이 없으면 키 입력을 그대로 넘긴다.
    private func handlePlaybackKey(_ key: PlaybackKeyMonitor.Key) -> Bool {
        guard case let .ready(timeline) = previewPlayer.loadState else { return false }
        switch key {
        case .playPause: previewPlayer.togglePlayPause()
        case .previousFrame: previewPlayer.stepFrame(by: -1, in: timeline)
        case .nextFrame: previewPlayer.stepFrame(by: 1, in: timeline)
        }
        return true
    }

    /// 저장에 성공하면 `true`. 닫기·종료 확인 창은 실패하면 창을 닫지 않는다.
    private func saveProject() -> Bool {
        do {
            try editor.save()
            return true
        } catch {
            Logger.project.error("프로젝트 저장 실패: \(error.localizedDescription, privacy: .public)")
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Backups

    /// 창이 열려 있는 동안 정해진 간격마다 저장하지 않은 변경을 백업본에 쓴다. 창이 닫히면 Task가 취소되어 멈춘다.
    private func writeBackupsPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: BackupPolicy.defaultInterval)
            guard !Task.isCancelled else { return }
            do {
                try editor.writeBackupIfNeeded()
            } catch {
                Logger.project.error("백업본 기록 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// 창이 앞에 있는 동안 Space·←/→를 미리보기 조작으로 받는다.
private struct PlaybackKeyHandling: ViewModifier {
    let handle: (PlaybackKeyMonitor.Key) -> Bool
    @State private var monitor = PlaybackKeyMonitor()
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content
            .onAppear { monitor.start(handler: handle) }
            .onDisappear { monitor.stop() }
            .onChange(of: controlActiveState, initial: true) { _, state in
                monitor.isWindowActive = state == .key
            }
    }
}

#if DEBUG
    private extension View {
        /// 디버그 메뉴에서 이름 끝에 표시를 붙여 저장하지 않은 변경 상태를 만들거나, 내용을 샘플 데이터로 바꾼다.
        func debugCommandValues(editor: ProjectEditor) -> some View {
            focusedSceneValue(\.makeUnsavedChange) {
                editor.applyDebugChange { $0.name += " ✎" }
            }
            .focusedSceneValue(\.fillSampleData) {
                editor.applyDebugChange { project in
                    project.assets = SampleData.project.assets
                    project.folders = SampleData.project.folders
                    project.sequences = SampleData.project.sequences
                }
            }
        }
    }
#endif

#Preview {
    // 미리보기에서는 저장하지 않도록 메모리 안의 저장소를 쓴다.
    let container = try! ModelContainer(
        for: ProjectRecord.self, ProjectBackupRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    MainWindowView(editor: ProjectEditor(project: SampleData.project, repository: SwiftDataProjectRepository(modelContext: container.mainContext)))
}
