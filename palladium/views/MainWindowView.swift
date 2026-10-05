import AppKit
import CoreMedia
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    /// 진행 중인 내보내기. 끝나거나 취소되면 `nil`.
    @State private var export: ExportJob?
    @State private var importReport: MediaImportReport?
    /// 프리미어 프로처럼 미디어 패널 선택, 미리보기에 연 원본, 타임라인 클립 선택은 서로 독립이다.
    @State private var selectedAssetID: MediaAsset.ID?
    /// 훑어보기(Quick Look) 창에 띄울 원본 파일.
    @State private var quickLookURL: URL?
    @State private var selectedClipIDs: Set<Clip.ID> = []
    /// 타임라인에서 클립·원본을 끄는 중인지. Esc로 끌기를 취소할 때 쓴다.
    @State private var isTimelineDragging = false
    @State private var timelineDragCancelCount = 0
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
        let currentSequence = editor.currentSequence
        // 인스펙터는 클립 하나를 골랐을 때만 속성을 보여준다.
        let selectedClip = selectedClipIDs.count == 1 ? selectedClipIDs.first.flatMap { currentSequence.clip(id: $0) } : nil
        let selectedClipAsset = project.assets.first { $0.id == selectedClip?.assetID }

        // 식이 길면 타입 검사가 끝나지 않으므로 단계별로 나눠 쌓는다.
        let window = splitView(currentSequence: currentSequence, selectedClip: selectedClip, selectedClipAsset: selectedClipAsset)
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
        let withCommands = window
            .focusedSceneValue(\.saveProject, saveAction)
            .focusedSceneValue(\.importMedia) { isImporterPresented = true }
            .focusedSceneValue(\.exportSequence, exportAction)
            .focusedSceneValue(\.splitClips, splitAction)
            .focusedSceneValue(\.isTimelineVisible, $isTimelineVisible)
            .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
            .focusedSceneValue(\.timelineScale, $timelineScale)
        let withBehaviors = withCommands
            .task { await writeBackupsPeriodically() }
            .modifier(EditorKeyHandling(handle: handleEditorKey))
            // 편집기 커맨드의 실행 취소를 창의 실행 취소 관리자(편집 > 실행 취소 ⌘Z)에 남긴다.
            .onChange(of: undoManager, initial: true) { _, undoManager in
                editor.undoManager = undoManager
            }
            .modifier(SequencePlayback(
                sequence: currentSequence,
                assets: project.assets,
                aspectRatio: aspectRatio,
                previewPlayer: previewPlayer,
                playheadTime: $playheadTime
            ))
            .quickLookPreview($quickLookURL)

        withBehaviors
            .sheet(item: $export) { job in
                ExportProgressView(job: job)
            }
            .onAppear {
                // 새 편집 창은 환경설정의 기본 화면비로 시작한다.
                if let stored = UserDefaults.standard.string(forKey: AppPreferences.defaultAspectRatioKey),
                   let preset = AspectRatioPreset(rawValue: stored)
                {
                    aspectRatio = preset
                }
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
    private func editorArea(currentSequence: EditSequence) -> some View {
        GeometryReader { geometry in
            let maxTimelineHeight = max(MainWindowMetrics.timelineMinHeight, geometry.size.height - MainWindowMetrics.previewMinHeight)

            VStack(spacing: 0) {
                PreviewPlayerView(
                    previewPlayer: previewPlayer,
                    hasProjectAssets: !editor.project.assets.isEmpty,
                    transformTarget: transformTarget(in: currentSequence),
                    renderSize: SequenceComposer.renderSize(for: aspectRatio),
                    setTransform: { clipID, transform in editor.setTransform(transform, for: clipID) }
                )
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
                        isDragging: $isTimelineDragging,
                        dragCancelCount: timelineDragCancelCount,
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
            dropAsset: { assetID, trackID, time in
                if let clipID = editor.placeAsset(assetID, onTrack: trackID, at: time) {
                    selectedClipIDs = [clipID]
                }
            },
            moveClip: { clipID, trackID, time in
                editor.moveClip(clipID, toTrack: trackID, at: time)
            },
            trimClip: { clipID, edge, delta in editor.trimClip(clipID, edge: edge, by: delta) },
            deleteClips: { clipIDs, ripple in
                editor.deleteClips(clipIDs, ripple: ripple)
                selectedClipIDs.subtract(clipIDs)
            },
            splitClips: { clipIDs in
                editor.splitClips(clipIDs, at: playheadTime)
            },
            openAsset: quickLook,
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
            },
            addMarker: { editor.addMarker(at: playheadTime) },
            renameMarker: { markerID, name in editor.renameMarker(markerID, to: name) },
            deleteMarker: { markerID in editor.deleteMarker(markerID) },
            setTrackAudio: { trackID, volume, isMuted in editor.setTrackAudio(volume: volume, isMuted: isMuted, for: trackID) },
            addTrack: { kind in editor.addTrack(kind: kind) },
            deleteTrack: { trackID in editor.deleteTrack(trackID) }
        )
    }

    /// 미디어 패널 · 가운데(미리보기 + 타임라인) · 인스펙터와 툴바. 본문 식이 길어 타입 검사가 느려지지 않도록 나눈다.
    private func splitView(currentSequence: EditSequence, selectedClip: Clip?, selectedClipAsset: MediaAsset?) -> some View {
        NavigationSplitView {
            MediaPanelView(
                editor: editor,
                selectedAssetID: $selectedAssetID,
                openAsset: quickLook,
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
            editorArea(currentSequence: currentSequence)
                // 가운데 영역은 0까지 줄어들 수 있게 해 양쪽 패널 폭을 먼저 지키고, 넘치는 내용은 잘라낸다.
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(
                clip: selectedClip,
                asset: selectedClipAsset,
                selectedClipCount: selectedClipIDs.count,
                setClipSource: { clipID, start, end in editor.setClipSource(clipID, start: start, end: end) },
                setTransform: { clipID, transform in editor.setTransform(transform, for: clipID) },
                setClipAudio: { clipID, volume, isMuted in editor.setClipAudio(volume: volume, isMuted: isMuted, for: clipID) }
            )
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
                importMedia: { isImporterPresented = true },
                exportSequence: exportAction
            )
        }
    }

    /// 미리보기에서 테두리로 옮기고 크기를 바꿀 클립. 클립 하나를 골랐고 화면에 그려지는(소리만 있지 않은) 경우만.
    private func transformTarget(in sequence: EditSequence) -> (clip: Clip, asset: MediaAsset)? {
        guard selectedClipIDs.count == 1,
              let clip = selectedClipIDs.first.flatMap({ sequence.clip(id: $0) }),
              let asset = editor.asset(id: clip.assetID),
              asset.kind != .audio
        else { return nil }
        return (clip, asset)
    }

    /// 파일 > 내보내기(⌘E)·툴바 버튼. 클립이 없으면 `nil`이라 비활성화된다.
    private var exportAction: (() -> Void)? {
        editor.currentSequence.duration > .zero ? { chooseExportDestination() } : nil
    }

    /// 저장 위치를 고른 뒤 현재 시퀀스를 툴바의 화면비로 내보낸다.
    private func chooseExportDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(editor.project.name) - \(editor.currentSequence.name).mp4"
        panel.message = "현재 시퀀스를 \(aspectRatio.widthRatio):\(aspectRatio.heightRatio) 화면비 MP4로 내보냅니다."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            startExport(to: url)
        }
    }

    private func startExport(to url: URL) {
        let job = ExportJob(fileName: url.lastPathComponent)
        let sequence = editor.currentSequence
        let assets = editor.project.assets
        let preset = aspectRatio
        job.task = Task {
            guard let composition = await SequenceComposer.makeComposition(
                sequence: sequence, assets: assets, aspectRatio: preset, resolveURL: MediaFileAccess.resolvedURL
            ) else {
                job.finish(error: "내보낼 클립이 없습니다.")
                return
            }
            do {
                try await SequenceExporter.export(composition, to: url) { fraction in
                    Task { @MainActor in job.progress = fraction }
                }
                job.finish(error: nil)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch is CancellationError {
                export = nil
            } catch {
                job.finish(error: error.localizedDescription)
            }
        }
        export = job
    }

    /// 원본을 훑어보기(Quick Look) 창으로 연다. 원본 전용 미리보기는 두지 않는다.
    private func quickLook(_ assetID: MediaAsset.ID) {
        guard let asset = editor.asset(id: assetID) else { return }
        quickLookURL = MediaFileAccess.resolvedURL(for: asset)
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
        case .selectAll:
            selectedClipIDs = Set(editor.currentSequence.tracks.flatMap(\.clips).map(\.id))
        case .escape:
            return releaseOneLevel()
        case .addMarker:
            editor.addMarker(at: playheadTime)
        }
        return true
    }

    /// Esc를 누를 때마다 가장 안쪽 상태부터 한 단계씩 푼다: 끄는 중인 편집 → 클립 선택 → 원본 선택.
    /// 풀 것이 없으면 키를 그대로 넘긴다.
    private func releaseOneLevel() -> Bool {
        if isTimelineDragging {
            timelineDragCancelCount += 1
        } else if !selectedClipIDs.isEmpty {
            selectedClipIDs = []
        } else if selectedAssetID != nil {
            selectedAssetID = nil
        } else {
            return false
        }
        return true
    }

    /// 편집 > 클립 분할(⌘B). 재생 헤드에서 나눌 클립이 없으면 `nil`이라 메뉴가 비활성화된다.
    private var splitAction: (() -> Void)? {
        let clipIDs = selectedClipIDs.isEmpty ? nil : selectedClipIDs
        guard editor.currentSequence.canSplit(at: playheadTime, clipIDs: clipIDs) else { return nil }
        return { timelineActions.splitClips(selectedClipIDs) }
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
            // 환경설정에서 바꾼 간격은 다음 백업부터 반영된다.
            let storedSeconds = UserDefaults.standard.integer(forKey: AppPreferences.backupIntervalSecondsKey)
            try? await Task.sleep(for: BackupPolicy.interval(fromStoredSeconds: storedSeconds))
            guard !Task.isCancelled else { return }
            do {
                try editor.writeBackupIfNeeded()
            } catch {
                Logger.project.error("백업본 기록 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// 시퀀스를 합성해 미리보기에 불러오고, 재생 헤드와 미리보기 위치를 서로 맞춘다.
private struct SequencePlayback: ViewModifier {
    let sequence: EditSequence
    let assets: [MediaAsset]
    let aspectRatio: AspectRatioPreset
    let previewPlayer: PreviewPlayer
    @Binding var playheadTime: CMTime

    func body(content: Content) -> some View {
        content
            // 시퀀스·원본·화면비가 바뀌면 다시 합성한다. 연달아 바뀔 때 매번 합성하지 않도록 잠깐 기다린다.
            .task(id: CompositionKey(sequence: sequence, assets: assets, aspectRatio: aspectRatio)) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let composition = await SequenceComposer.makeComposition(
                    sequence: sequence,
                    assets: assets,
                    aspectRatio: aspectRatio,
                    resolveURL: MediaFileAccess.resolvedURL
                )
                guard !Task.isCancelled else { return }
                previewPlayer.loadSequence(composition)
            }
            // 재생 중에는 재생 헤드가 미리보기를 따라가고, 재생 헤드를 옮기면(눈금자·마커) 미리보기가 그 위치로 간다.
            .onChange(of: previewPlayer.currentTime) { _, time in
                if abs((time - playheadTime).seconds) > SequenceComposer.frameDuration.seconds / 2 {
                    playheadTime = time
                }
            }
            .onChange(of: playheadTime) { _, time in
                guard case let .ready(timeline) = previewPlayer.loadState,
                      abs((time - previewPlayer.currentTime).seconds) > SequenceComposer.frameDuration.seconds / 2
                else { return }
                previewPlayer.seek(to: time, in: timeline)
            }
    }
}

/// 다시 합성할지 정하는 값. 이 중 하나라도 바뀌면 시퀀스를 다시 합성한다.
private struct CompositionKey: Equatable {
    let sequence: EditSequence
    let assets: [MediaAsset]
    let aspectRatio: AspectRatioPreset
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
