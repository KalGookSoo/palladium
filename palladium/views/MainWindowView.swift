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
    /// 자막 파일을 읽거나 쓰지 못했을 때의 안내.
    @State private var subtitleFileMessage: String?
    @State private var isImporterPresented = false
    /// 진행 중인 내보내기. 끝나거나 취소되면 `nil`.
    @State private var export: ExportJob?
    @State private var isBatchExportPresented = false
    @State private var importReport: MediaImportReport?
    /// 프리미어 프로처럼 미디어 패널 선택, 미리보기에 연 원본, 타임라인 클립 선택은 서로 독립이다.
    @State private var selectedAssetID: MediaAsset.ID?
    /// 훑어보기(Quick Look) 창에 띄울 원본 파일.
    @State private var quickLookURL: URL?
    @State private var selectedClipIDs: Set<Clip.ID> = []
    /// 미디어 패널 목록에 포커스가 있으면 ⌫는 원본 삭제(#60)라 타임라인 삭제로 가로채지 않는다.
    @State private var isMediaPanelFocused = false
    /// 자막 트랙에서 고른 자막. 클립 선택과 함께 있지 않는다.
    @State private var selectedSubtitleID: Subtitle.ID?
    /// 마스크 레인에서 고른 마스크(#59). 클립·자막 선택과 함께 있지 않는다.
    @State private var selectedMaskID: Mask.ID?
    /// 열린 트림 시트(#81).
    @State private var trimTarget: TrimTarget?
    /// `true`면 인스펙터 이름 칸에 포커스를 준다(F2·우클릭 > 이름 변경, #78). 인스펙터가 포커스를 준 뒤 되돌린다.
    @State private var isClipNameFocusRequested = false
    /// 타임라인에서 클립·원본을 끄는 중인지. Esc로 끌기를 취소할 때 쓴다.
    @State private var isTimelineDragging = false
    @State private var timelineDragCancelCount = 0
    @State private var playheadTime: CMTime = .zero
    @State private var timelineScale = TimelineScale(pointsPerSecond: 40)
    @State private var previewPlayer = PreviewPlayer()
    @State private var narration = NarrationRecorder()
    /// 정지 프레임을 저장하지 못했을 때의 안내.
    @State private var stillFrameMessage: String?
    /// 내레이션을 녹음하지 못했을 때의 안내.
    @State private var narrationMessage: String?
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
        let isShowingStillFrameMessage = Binding<Bool>(
            get: { stillFrameMessage != nil },
            set: {
                if !$0 {
                    stillFrameMessage = nil
                }
            }
        )
        let isShowingNarrationMessage = Binding<Bool>(
            get: { narrationMessage != nil },
            set: {
                if !$0 {
                    narrationMessage = nil
                }
            }
        )
        let isShowingSubtitleFileMessage = Binding<Bool>(
            get: { subtitleFileMessage != nil },
            set: {
                if !$0 {
                    subtitleFileMessage = nil
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
            .focusedSceneValue(\.batchExport, batchExportAction)
            .focusedSceneValue(\.exportStillFrame, stillFrameAction)
            .focusedSceneValue(\.importSubtitles) { chooseSubtitleFile() }
            .focusedSceneValue(\.exportSubtitles, exportSubtitlesAction)
            .focusedSceneValue(\.splitClips, splitAction)
            .focusedSceneValue(\.openTrimSheet, trimSheetAction)
            .focusedSceneValue(\.duplicateClips, selectedClipIDs.isEmpty ? nil : { timelineActions.duplicateClips(selectedClipIDs) })
            .focusedSceneValue(\.renameSelectedClip, selectedClip.map { clip in { beginRenamingClip(clip.id) } })
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
            // 클립·자막·마스크는 함께 고르지 않는다. 하나를 고르면 나머지 선택을 푼다.
            .onChange(of: selectedSubtitleID) {
                if selectedSubtitleID != nil {
                    selectedClipIDs = []
                    selectedMaskID = nil
                }
            }
            .onChange(of: selectedMaskID) {
                if selectedMaskID != nil {
                    selectedClipIDs = []
                    selectedSubtitleID = nil
                }
            }
            .onChange(of: selectedClipIDs) {
                if !selectedClipIDs.isEmpty {
                    selectedSubtitleID = nil
                    selectedMaskID = nil
                }
            }

        withBehaviors
            .sheet(item: $export) { job in
                ExportProgressView(job: job)
            }
            .sheet(item: $trimTarget) { target in
                TrimSheetView(editor: editor, target: target)
            }
            .sheet(isPresented: $isBatchExportPresented) {
                BatchExportView(
                    sequences: editor.project.sequences,
                    initialAspectRatio: aspectRatio,
                    suggestedAspectRatio: suggestedAspectRatio(for:),
                    start: startBatchExport
                )
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
            .alert("정지 프레임을 저장하지 못했습니다", isPresented: isShowingStillFrameMessage) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(stillFrameMessage ?? "")
            }
            .alert("내레이션 녹음", isPresented: isShowingNarrationMessage) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(narrationMessage ?? "")
            }
            .alert("자막 파일", isPresented: isShowingSubtitleFileMessage) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(subtitleFileMessage ?? "")
            }
        #if DEBUG
            .debugCommandValues(editor: editor)
        #endif
    }

    /// 가져온 원본은 "분류 안 됨"에 추가되고 저장하지 않은 변경이 된다. 마지막으로 가져온(또는 이미 있던) 원본을 선택한다.
    private func importMedia(from urls: [URL]) {
        Task {
            let report = await editor.importMedia(from: urls)
            ProxyGenerator.shared.generateIfNeeded(for: report.imported, threshold: proxyThreshold)
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
                    setTransform: { clipID, transform in editor.setTransform(transform, for: clipID) },
                    maskTarget: currentSequence.masks.first { $0.id == selectedMaskID },
                    setMaskArea: setMaskArea,
                    subtitleTarget: currentSequence.subtitles.first { $0.id == selectedSubtitleID },
                    setSubtitlePosition: { subtitleID, centerX, centerY in editor.setSubtitlePosition(subtitleID, centerX: centerX, centerY: centerY) },
                    narrationStartedAt: narration.startedAt,
                    toggleNarration: toggleNarration
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
                        selectedSubtitleID: $selectedSubtitleID,
                        selectedMaskID: $selectedMaskID,
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
        let paste: (() -> Void)? = editor.clipboard == nil ? nil : { pasteAtPlayhead() }
        return TimelineActions(
            dropAsset: { assetID, trackID, time in
                let hadPicture = editor.currentSequence.tracks.contains { $0.kind == .video && !$0.clips.isEmpty }
                if let clipID = editor.placeAsset(assetID, onTrack: trackID, at: time) {
                    selectedClipIDs = [clipID]
                    if !hadPicture {
                        matchAspectRatio(toAsset: assetID)
                    }
                }
            },
            moveClip: { clipID, trackID, time in
                editor.moveClip(clipID, toTrack: trackID, at: time)
            },
            trimClip: { clipID, edge, delta in editor.trimClip(clipID, edge: edge, by: delta) },
            rollClip: { clipID, edge, delta in editor.rollClip(clipID, edge: edge, by: delta) },
            slipClip: { clipID, delta in editor.slipClip(clipID, by: delta) },
            slideClip: { clipID, delta in editor.slideClip(clipID, by: delta) },
            deleteClips: { clipIDs, ripple in
                editor.deleteClips(clipIDs, ripple: ripple)
                selectedClipIDs.subtract(clipIDs)
            },
            splitClips: { clipIDs in
                editor.splitClips(clipIDs, at: playheadTime)
            },
            renameClip: beginRenamingClip,
            setClipColorLabel: { clipIDs, colorLabel in editor.setClipColorLabel(colorLabel, for: clipIDs) },
            copyClips: { clipIDs in editor.copyClips(clipIDs) },
            cutClips: { clipIDs in
                editor.cutClips(clipIDs)
                selectedClipIDs.subtract(clipIDs)
            },
            duplicateClips: { clipIDs in
                let duplicated = editor.duplicateClips(clipIDs)
                if !duplicated.isEmpty {
                    selectedClipIDs = duplicated
                }
            },
            openTrimSheet: { clipID in trimTarget = TrimTarget(kind: .clip(clipID)) },
            paste: paste,
            openAsset: quickLook,
            revealAsset: { assetID in selectedAssetID = assetID },
            switchSequence: { sequenceID in
                editor.switchToSequence(sequenceID)
                selectedClipIDs = []
                selectedSubtitleID = nil
                selectedMaskID = nil
            },
            addSequence: {
                editor.addSequence(named: "")
                selectedClipIDs = []
                selectedSubtitleID = nil
                selectedMaskID = nil
            },
            renameSequence: { sequenceID, name in editor.renameSequence(sequenceID, to: name) },
            deleteSequence: { sequenceID in
                editor.deleteSequence(sequenceID)
                selectedClipIDs = []
                selectedSubtitleID = nil
                selectedMaskID = nil
            },
            addMarker: { editor.addMarker(at: playheadTime) },
            renameMarker: { markerID, name in editor.renameMarker(markerID, to: name) },
            deleteMarker: { markerID in editor.deleteMarker(markerID) },
            setTransition: { clipID, transition in editor.setTransition(transition, forClip: clipID) },
            addSubtitle: addSubtitleAtPlayhead,
            setSubtitleRange: { subtitleID, start, end in editor.setSubtitleRange(subtitleID, start: start, end: end) },
            deleteSubtitle: deleteSubtitle,
            addMask: {
                selectedMaskID = editor.addMask(at: playheadTime)
                isInspectorPresented = true
            },
            setMaskRange: { maskID, start, end in editor.setMaskRange(maskID, start: start, end: end) },
            deleteMask: deleteMask,
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
                importFiles: importMedia(from:),
                isListFocused: $isMediaPanelFocused,
                openTrimSheet: { assetID in trimTarget = TrimTarget(kind: .asset(assetID)) }
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
                isNameFocusRequested: $isClipNameFocusRequested,
                multipleSelectionAdjustment: selectedClipIDs.count > 1 ? pictureClips(in: currentSequence).first?.colorAdjustment : nil,
                setColorAdjustment: { adjustment in
                    editor.setColorAdjustment(adjustment, for: Set(pictureClips(in: currentSequence).map(\.id)))
                },
                renameClip: { clipID, name in editor.renameClip(clipID, to: name) },
                setClipSource: { clipID, start, end in editor.setClipSource(clipID, start: start, end: end) },
                setTransform: { clipID, transform in editor.setTransform(transform, for: clipID) },
                setClipAudio: { clipID, volume, isMuted in editor.setClipAudio(volume: volume, isMuted: isMuted, for: clipID) },
                setClipSpeed: { clipID, speed in editor.setClipSpeed(speed, for: clipID) },
                maximumTransitionDuration: selectedClip.flatMap { clip in
                    currentSequence.tracks.first { $0.clips.contains { $0.id == clip.id } }?.maximumTransitionDuration(into: clip)
                } ?? .zero,
                setTransition: { clipID, transition in editor.setTransition(transition, forClip: clipID) },
                setAudioCrossfade: { clipID, duration in editor.setAudioCrossfade(duration, forClip: clipID) },
                subtitle: currentSequence.subtitles.first { $0.id == selectedSubtitleID },
                updateSubtitle: { subtitleID, text, style in editor.updateSubtitle(subtitleID, text: text, style: style) },
                setSubtitlePosition: { subtitleID, centerX, centerY in editor.setSubtitlePosition(subtitleID, centerX: centerX, centerY: centerY) },
                renderSize: SequenceComposer.renderSize(for: aspectRatio),
                setSubtitleRange: { subtitleID, start, end in editor.setSubtitleRange(subtitleID, start: start, end: end) },
                deleteSubtitle: deleteSubtitle,
                mask: currentSequence.masks.first { $0.id == selectedMaskID },
                updateMask: { mask in editor.updateMask(mask) },
                setMaskRange: { maskID, start, end in editor.setMaskRange(maskID, start: start, end: end) },
                deleteMask: deleteMask
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

    /// 시퀀스에 처음 영상·이미지를 놓으면 툴바 화면비를 그 원본 방향에 맞춘다(세로 영상이면 9:16).
    private func matchAspectRatio(toAsset assetID: MediaAsset.ID) {
        guard let asset = editor.asset(id: assetID), asset.kind != .audio else { return }
        Task {
            if let size = await ClipContentProvider.shared.contentSize(for: asset), let preset = AspectRatioPreset.closest(to: size) {
                aspectRatio = preset
            }
        }
    }

    /// 시퀀스의 메인 영상 트랙(영상 1)에 놓인 영상·이미지 방향에 맞는 화면비. 길이로 가중한다. 영상·이미지가 없으면 `nil`.
    private func suggestedAspectRatio(for sequence: EditSequence) async -> AspectRatioPreset? {
        guard let mainTrack = sequence.tracks.last(where: { $0.kind == .video }) else { return nil }
        var contents: [(size: CGSize, duration: Double)] = []
        for clip in mainTrack.clips {
            guard let asset = editor.asset(id: clip.assetID), asset.kind != .audio,
                  let size = await ClipContentProvider.shared.contentSize(for: asset)
            else { continue }
            contents.append((size, clip.timelineDuration.seconds))
        }
        return AspectRatioPreset.suggested(for: contents)
    }

    /// 고른 화면비가 원본 방향과 다르면 내보내기 전에 알릴 문구.
    static func aspectRatioWarning(chosen: AspectRatioPreset, suggested: AspectRatioPreset?) -> String? {
        guard let suggested, suggested != chosen else { return nil }
        return "⚠️ \(suggested.orientationTitle)을 \(chosen.title)로 내보내면 빈 곳이 검게 채워지고 영상이 작아집니다. 원본 그대로 내려면 툴바 화면비를 \(suggested.title)로 바꾸세요."
    }

    /// 파일 > 내보내기(⌘E)·툴바 버튼. 클립이 없으면 `nil`이라 비활성화된다.
    private var exportAction: (() -> Void)? {
        editor.currentSequence.duration > .zero ? { chooseExportDestination() } : nil
    }

    /// 저장 위치를 고른 뒤 현재 시퀀스를 툴바의 화면비로 내보낸다.
    private func chooseExportDestination() {
        Task {
            let warning = Self.aspectRatioWarning(chosen: aspectRatio, suggested: await suggestedAspectRatio(for: editor.currentSequence))
            showExportPanel(warning: warning)
        }
    }

    private func showExportPanel(warning: String?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(editor.project.name) - \(editor.currentSequence.name).mp4"
        let summary = "현재 시퀀스를 \(aspectRatio.title) 화면비 MP4로 내보냅니다. 프레임레이트는 원본을 따릅니다."
        panel.message = warning.map { "\(summary)\n\($0)" } ?? summary
        let options = NSHostingView(rootView: Form { ExportOptionsView() }.padding(12).frame(width: 340))
        options.frame.size = options.fittingSize
        panel.accessoryView = options
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
        let options = ExportOptionsView.current
        job.task = Task {
            guard let composition = await SequenceComposer.makeComposition(
                sequence: sequence, assets: assets, aspectRatio: preset, resolution: options.resolution, resolveURL: MediaFileAccess.resolvedURL
            ) else {
                job.finish(error: "내보낼 클립이 없습니다.")
                return
            }
            do {
                try await SequenceExporter.export(composition, to: url, codec: options.codec) { fraction in
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

    /// 파일 > 여러 시퀀스 내보내기(⇧⌘E). 내보낼 시퀀스가 없으면 `nil`이라 비활성화된다.
    private var batchExportAction: (() -> Void)? {
        editor.project.sequences.contains { $0.duration > .zero } ? { isBatchExportPresented = true } : nil
    }

    /// 고른 시퀀스를 차례로 내보낸다. 하나가 실패해도 다음 시퀀스로 넘어간다.
    private func startBatchExport(sequenceIDs: [EditSequence.ID], preset: AspectRatioPreset, folder: URL) -> BatchExportJob {
        let sequences = sequenceIDs.compactMap { id in editor.project.sequences.first { $0.id == id } }
        let names = sequences.map { "\(editor.project.name) - \($0.name)" }
        let destinations = BatchExportJob.destinations(for: names, in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        let job = BatchExportJob(items: zip(sequences, destinations).map { BatchExportJob.Item(sequenceID: $0.id, destination: $1) })
        let assets = editor.project.assets
        let options = ExportOptionsView.current
        job.task = Task {
            await job.run { item, progress in
                guard let sequence = sequences.first(where: { $0.id == item.sequenceID }),
                      let composition = await SequenceComposer.makeComposition(
                          sequence: sequence, assets: assets, aspectRatio: preset, resolution: options.resolution, resolveURL: MediaFileAccess.resolvedURL
                      )
                else { throw SequenceExporter.ExportError.noPicture }
                try await SequenceExporter.export(composition, to: item.destination, codec: options.codec, progress: progress)
            }
        }
        return job
    }

    /// 파일 > 정지 프레임 저장. 재생 헤드에 그릴 화면이 없으면 `nil`이라 비활성화된다.
    private var stillFrameAction: (() -> Void)? {
        playheadTime < editor.currentSequence.duration ? { chooseStillFrameDestination() } : nil
    }

    /// 재생 헤드의 프레임을 툴바 화면비와 내보내기 해상도의 PNG로 저장한다. 미리보기에 보이던 프레임과 같다.
    private func chooseStillFrameDestination() {
        let time = playheadTime
        let sequence = editor.currentSequence
        let assets = editor.project.assets
        let preset = aspectRatio
        let resolution = ExportOptionsView.current.resolution
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let timeText = Duration.seconds(time.seconds).formatted(.time(pattern: .minuteSecond)).replacingOccurrences(of: ":", with: ".")
        panel.nameFieldStringValue = "\(editor.project.name) - \(sequence.name) \(timeText).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    guard let composition = await SequenceComposer.makeComposition(
                        sequence: sequence, assets: assets, aspectRatio: preset, resolution: resolution, resolveURL: MediaFileAccess.resolvedURL
                    ) else { throw SequenceExporter.ExportError.noPicture }
                    try await SequenceExporter.exportStillFrame(composition, at: time, to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    stillFrameMessage = error.localizedDescription
                }
            }
        }
    }

    /// 파일 > 자막 내보내기. 자막이 없으면 `nil`이라 비활성화된다.
    private var exportSubtitlesAction: (() -> Void)? {
        editor.currentSequence.subtitles.isEmpty ? nil : { saveSubtitleFile() }
    }

    /// 파일 > 자막 가져오기. 고른 SRT 파일의 자막을 현재 시퀀스에 더한다.
    private func chooseSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = "현재 시퀀스에 더할 SRT 자막 파일을 고르세요."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16))
            let count = text.map { editor.importSubtitles(fromSRT: $0) } ?? 0
            if count == 0 {
                subtitleFileMessage = "\(url.lastPathComponent)에서 자막을 읽지 못했습니다. UTF-8 SRT 파일인지 확인하세요."
            }
        }
    }

    /// 파일 > 자막 내보내기. 현재 시퀀스의 자막을 SRT 파일로 저장한다.
    private func saveSubtitleFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(editor.project.name) - \(editor.currentSequence.name).srt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try editor.currentSubtitlesSRT.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                subtitleFileMessage = error.localizedDescription
            }
        }
    }

    /// 원본을 훑어보기(Quick Look) 창으로 연다. 원본 전용 미리보기는 두지 않는다.
    private func quickLook(_ assetID: MediaAsset.ID) {
        guard let asset = editor.asset(id: assetID) else { return }
        quickLookURL = MediaFileAccess.resolvedURL(for: asset)
    }

    /// 처리하지 않는 키(미리보기에 원본이 없을 때의 재생 키, 고른 클립이 없을 때의 삭제)는 그대로 넘긴다.
    private func handleEditorKey(_ key: EditorKeyMonitor.Key) -> Bool {
        // 자막을 골랐으면 ←/→는 프레임 이동 대신 자막을 옮긴다(#82).
        if selectedSubtitleID != nil, key == .previousFrame || key == .nextFrame {
            return nudgeSelectedSubtitle(key)
        }
        switch key {
        case .moveUp, .moveDown, .moveLeftLarge, .moveRightLarge, .moveUpLarge, .moveDownLarge:
            return nudgeSelectedSubtitle(key)
        case .playPause, .previousFrame, .nextFrame:
            guard case let .ready(timeline) = previewPlayer.loadState else { return false }
            switch key {
            case .playPause: previewPlayer.togglePlayPause()
            case .previousFrame: previewPlayer.stepFrame(by: -1, in: timeline)
            default: previewPlayer.stepFrame(by: 1, in: timeline)
            }
        case .deleteSelection, .rippleDeleteSelection:
            guard !isMediaPanelFocused else { return false }
            if let selectedSubtitleID {
                deleteSubtitle(selectedSubtitleID)
                return true
            }
            if let selectedMaskID {
                deleteMask(selectedMaskID)
                return true
            }
            guard !selectedClipIDs.isEmpty else { return false }
            timelineActions.deleteClips(selectedClipIDs, key == .rippleDeleteSelection)
        case .selectAll:
            selectedClipIDs = Set(editor.currentSequence.tracks.flatMap(\.clips).map(\.id))
        case .escape:
            return releaseOneLevel()
        case .addMarker:
            editor.addMarker(at: playheadTime)
        case .addSubtitle:
            addSubtitleAtPlayhead()
        case .toggleNarration:
            toggleNarration()
        case .copy, .cut:
            return copySelection(cut: key == .cut)
        case .paste:
            guard !isMediaPanelFocused, editor.clipboard != nil else { return false }
            pasteAtPlayhead()
        }
        return true
    }

    /// 고른 자막을 방향키로 옮긴다(#82). 한 번에 화면의 0.5%, ⇧와 함께 5%.
    private func nudgeSelectedSubtitle(_ key: EditorKeyMonitor.Key) -> Bool {
        guard !isMediaPanelFocused, let selectedSubtitleID else { return false }
        let small = 0.005
        let large = 0.05
        let (dx, dy): (Double, Double) = switch key {
        case .previousFrame: (-small, 0)
        case .nextFrame: (small, 0)
        case .moveUp: (0, -small)
        case .moveDown: (0, small)
        case .moveLeftLarge: (-large, 0)
        case .moveRightLarge: (large, 0)
        case .moveUpLarge: (0, -large)
        case .moveDownLarge: (0, large)
        default: (0, 0)
        }
        editor.nudgeSubtitle(selectedSubtitleID, dx: dx, dy: dy, renderSize: SequenceComposer.renderSize(for: aspectRatio))
        return true
    }

    /// 고른 자막·마스크·클립을 복사하거나 잘라낸다(#62). 고른 것이 없거나 미디어 패널에 포커스가 있으면 키를 넘긴다.
    private func copySelection(cut: Bool) -> Bool {
        guard !isMediaPanelFocused else { return false }
        if let selectedSubtitleID {
            editor.copySubtitle(selectedSubtitleID)
            if cut {
                deleteSubtitle(selectedSubtitleID)
            }
        } else if let selectedMaskID {
            editor.copyMask(selectedMaskID)
            if cut {
                deleteMask(selectedMaskID)
            }
        } else if !selectedClipIDs.isEmpty {
            if cut {
                timelineActions.cutClips(selectedClipIDs)
            } else {
                editor.copyClips(selectedClipIDs)
            }
        } else {
            return false
        }
        return true
    }

    /// 재생 헤드에 붙이고 붙인 것을 고른다.
    private func pasteAtPlayhead() {
        switch editor.pasteClips(at: playheadTime) {
        case let .clips(clipIDs):
            selectedSubtitleID = nil
            selectedMaskID = nil
            selectedClipIDs = clipIDs
        case let .subtitle(subtitleID):
            selectedClipIDs = []
            selectedMaskID = nil
            selectedSubtitleID = subtitleID
        case let .mask(maskID):
            selectedClipIDs = []
            selectedSubtitleID = nil
            selectedMaskID = maskID
        case nil:
            break
        }
    }

    /// Esc를 누를 때마다 가장 안쪽 상태부터 한 단계씩 푼다: 끄는 중인 편집 → 클립 선택 → 원본 선택.
    /// 풀 것이 없으면 키를 그대로 넘긴다.
    private func releaseOneLevel() -> Bool {
        if isTimelineDragging {
            timelineDragCancelCount += 1
        } else if selectedSubtitleID != nil {
            selectedSubtitleID = nil
        } else if selectedMaskID != nil {
            selectedMaskID = nil
        } else if !selectedClipIDs.isEmpty {
            selectedClipIDs = []
        } else if selectedAssetID != nil {
            selectedAssetID = nil
        } else {
            return false
        }
        return true
    }

    /// 환경설정의 프록시 기준(#43).
    private var proxyThreshold: ProxyThreshold {
        UserDefaults.standard.string(forKey: AppPreferences.proxyThresholdKey).flatMap(ProxyThreshold.init(rawValue:)) ?? .defaultValue
    }

    /// 내레이션 녹음을 시작하거나 멈춘다(#10). 시작하면 재생 헤드부터 미리보기를 재생하고, 헤드폰이 아니면 소리를 끈다.
    /// 멈추면 녹음 파일을 가져와 녹음을 시작한 시각에 오디오 클립으로 놓고 고른다.
    private func toggleNarration() {
        if narration.isRecording {
            previewPlayer.pause()
            previewPlayer.setMutedForRecording(false)
            guard let result = narration.stop() else { return }
            Task {
                if let clipID = await editor.addNarration(from: result.url, at: result.startTime) {
                    selectedClipIDs = [clipID]
                } else {
                    narrationMessage = "녹음한 파일을 가져오지 못했습니다: \(result.url.lastPathComponent)"
                }
            }
            return
        }
        let startTime = playheadTime
        Task {
            do {
                try await narration.start(at: startTime)
                previewPlayer.setMutedForRecording(!AudioOutputRoute.isHeadphonesConnected())
                previewPlayer.play()
            } catch {
                narrationMessage = error.localizedDescription
            }
        }
    }

    /// 재생 헤드에 자막을 두고 골라, 인스펙터에서 바로 글자를 입력하게 한다.
    private func addSubtitleAtPlayhead() {
        selectedSubtitleID = editor.addSubtitle(at: playheadTime)
        isInspectorPresented = true
    }

    private func deleteMask(_ maskID: Mask.ID) {
        editor.deleteMask(maskID)
        if selectedMaskID == maskID {
            selectedMaskID = nil
        }
    }

    private func setMaskArea(_ maskID: Mask.ID, _ area: MaskArea) {
        guard var mask = editor.currentSequence.masks.first(where: { $0.id == maskID }) else { return }
        mask.area = area
        editor.updateMask(mask)
    }

    private func deleteSubtitle(_ subtitleID: Subtitle.ID) {
        editor.deleteSubtitle(subtitleID)
        if selectedSubtitleID == subtitleID {
            selectedSubtitleID = nil
        }
    }

    /// 고른 클립 중 그림이 있는(영상·이미지) 클립. 색보정은 이 클립들에만 적용한다(#61). 타임라인 순서(트랙, 시각)다.
    private func pictureClips(in sequence: EditSequence) -> [Clip] {
        sequence.tracks.flatMap(\.clips).filter { clip in
            selectedClipIDs.contains(clip.id) && editor.asset(id: clip.assetID)?.kind != .audio
        }
    }

    /// 클립 하나를 고르고 인스펙터 맨 위 이름 칸에서 별칭을 입력받는다(#78).
    private func beginRenamingClip(_ clipID: Clip.ID) {
        selectedClipIDs = [clipID]
        selectedSubtitleID = nil
        selectedMaskID = nil
        isInspectorPresented = true
        isClipNameFocusRequested = true
    }

    /// 편집 > 트림…(⌘T, #81). 미디어 패널에 포커스가 있으면 고른 항목을, 아니면 고른 클립 하나를 연다. 이미지는 열지 않는다.
    private var trimSheetAction: (() -> Void)? {
        if isMediaPanelFocused, let selectedAssetID, editor.asset(id: selectedAssetID)?.isTrimmable == true {
            return { trimTarget = TrimTarget(kind: .asset(selectedAssetID)) }
        }
        guard selectedClipIDs.count == 1, let clipID = selectedClipIDs.first,
              let clip = editor.currentSequence.clip(id: clipID), editor.asset(id: clip.assetID)?.isTrimmable == true
        else { return nil }
        return { trimTarget = TrimTarget(kind: .clip(clipID)) }
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
    /// 재생 헤드와 미리보기 위치가 이만큼(60fps 반 프레임)보다 어긋날 때만 서로 맞춘다.
    private static let playheadTolerance = 1.0 / 120
    let sequence: EditSequence
    let assets: [MediaAsset]
    let aspectRatio: AspectRatioPreset
    let previewPlayer: PreviewPlayer
    @Binding var playheadTime: CMTime

    func body(content: Content) -> some View {
        content
            // 시퀀스·원본·화면비가 바뀌면 다시 합성한다. 연달아 바뀔 때 매번 합성하지 않도록 잠깐 기다린다.
            // 프록시가 생기거나 없어져도 다시 합성해 미리보기가 그 파일을 쓰게 한다(#43).
            .task(id: CompositionKey(sequence: sequence, assets: assets, aspectRatio: aspectRatio, proxyRevision: ProxyGenerator.shared.revision)) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let composition = await SequenceComposer.makeComposition(
                    sequence: sequence,
                    assets: assets,
                    aspectRatio: aspectRatio,
                    resolveURL: ProxyGenerator.previewURL
                )
                guard !Task.isCancelled else { return }
                previewPlayer.loadSequence(composition)
            }
            // 재생 중에는 재생 헤드가 미리보기를 따라가고, 재생 헤드를 옮기면(눈금자·마커) 미리보기가 그 위치로 간다.
            .onChange(of: previewPlayer.currentTime) { _, time in
                if abs((time - playheadTime).seconds) > Self.playheadTolerance {
                    playheadTime = time
                }
            }
            .onChange(of: playheadTime) { _, time in
                guard case let .ready(timeline) = previewPlayer.loadState,
                      abs((time - previewPlayer.currentTime).seconds) > Self.playheadTolerance
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
    let proxyRevision: Int
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
