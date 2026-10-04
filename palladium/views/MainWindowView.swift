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
    static let previewMinHeight = 240.0
    static let timelineMinHeight = 160.0
    static let timelineIdealHeight = 240.0
}

struct MainWindowView: View {
    @State private var isTimelineVisible = true
    /// 사용자가 경계를 끌었을 때만 바뀐다. 미리보기에 무엇을 열든 이 높이를 유지한다.
    @State private var timelineHeight = MainWindowMetrics.timelineIdealHeight
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
    @State private var selectedClipIDs: Set<Clip.ID> = []
    @State private var playheadTime: CMTime = .zero
    @State private var timelineScale = TimelineScale(pointsPerSecond: 40)
    @State private var previewPlayer = PreviewPlayer()
    @Environment(\.undoManager) private var undoManager

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
        let currentSequence = editor.currentSequence
        // 인스펙터는 클립 하나를 골랐을 때만 속성을 보여준다.
        let selectedClip = selectedClipIDs.count == 1 ? selectedClipIDs.first.flatMap { currentSequence.clip(id: $0) } : nil
        let selectedClipAsset = project.assets.first { $0.id == selectedClip?.assetID }

        NavigationSplitView {
            MediaPanelView(
                editor: editor,
                selectedAssetID: $selectedAssetID,
                openAsset: { assetID in openedAssetID = assetID },
                importFiles: importMedia(from:)
            )
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
            editorArea(openedAsset: openedAsset, currentSequence: currentSequence)
                // 가운데 영역은 0까지 줄어들 수 있게 해 양쪽 패널 폭을 먼저 지키고, 넘치는 내용은 잘라낸다.
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(clip: selectedClip, asset: selectedClipAsset, selectedClipCount: selectedClipIDs.count)
                .inspectorColumnWidth(
                    min: MainWindowMetrics.inspectorMinWidth,
                    ideal: MainWindowMetrics.inspectorIdealWidth,
                    max: MainWindowMetrics.inspectorMaxWidth
                )
        }
        .toolbar {
            MainWindowToolbar(
                aspectRatio: $aspectRatio,
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
        .modifier(EditorKeyHandling(handle: handleEditorKey))
        // 편집기 커맨드의 실행 취소를 창의 실행 취소 관리자(편집 > 실행 취소 ⌘Z)에 남긴다.
        .onChange(of: undoManager, initial: true) { _, undoManager in
            editor.undoManager = undoManager
        }
        .task(id: openedAssetID) {
            // 이미지는 플레이어로 열지 않는다. 앞서 열려 있던 영상은 멈추고 비운다.
            let playableAsset = openedAsset.flatMap { $0.kind == .image ? nil : $0 }
            await previewPlayer.load(url: playableAsset.map(MediaFileAccess.resolvedURL))
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

    /// 미리보기 아래에 타임라인을 둔다. `VSplitView`는 미리보기에 연 원본이 바뀌면 내용 크기에 맞춰 경계를 다시 나눠
    /// 사용자가 맞춘 높이가 풀리므로(#51), 타임라인 높이를 직접 들고 경계를 끌 때만 바꾼다.
    /// 창 높이가 바뀌면 미리보기가 늘거나 줄고, 미리보기가 최소 높이보다 작아지면 타임라인을 줄여 보여준다.
    private func editorArea(openedAsset: MediaAsset?, currentSequence: EditSequence) -> some View {
        GeometryReader { geometry in
            let maxTimelineHeight = max(MainWindowMetrics.timelineMinHeight, geometry.size.height - MainWindowMetrics.previewMinHeight)

            VStack(spacing: 0) {
                PreviewPlayerView(asset: openedAsset, previewPlayer: previewPlayer, hasProjectAssets: !editor.project.assets.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dropDestination(for: URL.self) { urls, _ in
                        importMedia(from: urls)
                        return true
                    }
                    // 타임라인을 접고 펴는 버튼은 툴바가 아니라 타임라인과 맞닿은 미리보기 오른쪽 위에 둔다.
                    .overlay(alignment: .topTrailing) {
                        Button {
                            isTimelineVisible.toggle()
                        } label: {
                            Label("타임라인", systemImage: "rectangle.bottomhalf.inset.filled")
                                .labelStyle(.iconOnly)
                                .padding(6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(ShortcutGuide.toggleTimeline.helpText)
                        .padding(8)
                    }
                if isTimelineVisible {
                    TimelineResizeHandle(
                        timelineHeight: $timelineHeight,
                        heightRange: MainWindowMetrics.timelineMinHeight ... maxTimelineHeight
                    )
                    TimelineEditorView(
                        sequence: currentSequence,
                        allSequences: editor.project.sequences,
                        assets: editor.project.assets,
                        selectedClipIDs: $selectedClipIDs,
                        playheadTime: $playheadTime,
                        scale: $timelineScale,
                        actions: timelineActions
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: min(timelineHeight, maxTimelineHeight))
                }
            }
        }
    }

    /// 타임라인의 편집 요청을 편집기 커맨드로 옮긴다. 화면 상태(선택, 미리보기에 연 원본)는 여기서 바꾼다.
    private var timelineActions: TimelineActions {
        TimelineActions(
            dropAsset: { assetID, trackID, time, mode in
                if let clipID = editor.placeAsset(assetID, onTrack: trackID, at: time, mode: mode) {
                    selectedClipIDs = [clipID]
                }
            },
            moveClip: { clipID, trackID, time, mode in
                editor.moveClip(clipID, toTrack: trackID, at: time, mode: mode)
            },
            deleteClips: { clipIDs, ripple in
                editor.deleteClips(clipIDs, ripple: ripple)
                selectedClipIDs.subtract(clipIDs)
            },
            splitClips: { clipIDs in
                editor.splitClips(clipIDs, at: playheadTime)
            },
            openAsset: { assetID in openedAssetID = assetID },
            revealAsset: { assetID in selectedAssetID = assetID },
            switchSequence: { sequenceID in
                editor.switchToSequence(sequenceID)
                selectedClipIDs = []
            },
            addSequence: {
                editor.addSequence(named: "")
                selectedClipIDs = []
            },
            renameSequence: { sequenceID, name in editor.renameSequence(sequenceID, to: name) },
            deleteSequence: { sequenceID in
                editor.deleteSequence(sequenceID)
                selectedClipIDs = []
            }
        )
    }

    /// 처리하지 않는 키(미리보기에 원본이 없을 때의 재생 키, 고른 클립이 없을 때의 삭제)는 그대로 넘긴다.
    private func handleEditorKey(_ key: EditorKeyMonitor.Key) -> Bool {
        switch key {
        case .playPause, .previousFrame, .nextFrame:
            guard case let .ready(timeline) = previewPlayer.loadState else { return false }
            switch key {
            case .playPause: previewPlayer.togglePlayPause()
            case .previousFrame: previewPlayer.stepFrame(by: -1, in: timeline)
            default: previewPlayer.stepFrame(by: 1, in: timeline)
            }
        case .deleteSelection, .rippleDeleteSelection:
            guard !selectedClipIDs.isEmpty else { return false }
            timelineActions.deleteClips(selectedClipIDs, key == .rippleDeleteSelection)
        case .splitAtPlayhead:
            timelineActions.splitClips(selectedClipIDs)
        case .selectAll:
            selectedClipIDs = Set(editor.currentSequence.tracks.flatMap(\.clips).map(\.id))
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

/// 미리보기와 타임라인 사이의 경계. 위아래로 끌어 타임라인 높이를 바꾼다.
/// 기본 구분선보다 조금 굵은 막대로 그려, 두 영역이 다른 부품이고 이 막대를 잡을 수 있다는 걸 드러낸다.
/// 막대만으로는 잡기 어려워 위아래 여백까지 끌기를 받는다.
private struct TimelineResizeHandle: View {
    static let thickness = 2.0

    @Binding var timelineHeight: Double
    let heightRange: ClosedRange<Double>
    @State private var dragStartHeight: Double?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: Self.thickness)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(
                // 경계가 끌리며 움직이므로 이동량은 창 기준 좌표로 잰다.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let startHeight = dragStartHeight ?? timelineHeight
                        dragStartHeight = startHeight
                        timelineHeight = min(max(startHeight - value.translation.height, heightRange.lowerBound), heightRange.upperBound)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}

/// 창이 앞에 있는 동안 Space·←/→(미리보기)와 Delete·⌘B·⌘A(타임라인)를 받는다.
private struct EditorKeyHandling: ViewModifier {
    let handle: (EditorKeyMonitor.Key) -> Bool
    @State private var monitor = EditorKeyMonitor()
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
