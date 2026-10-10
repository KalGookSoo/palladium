import AppKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

enum TimelineMetrics {
    /// 위 줄 시간 글자, 아래 줄 눈금·재생 헤드 머리(#79).
    static let rulerHeight = 30.0
    static let trackHeight = 44.0
    /// 눈금자 아래 자막·마스크 레인의 높이.
    static let rangeLaneHeight = 28.0
    static let clipVerticalInset = 4.0
    static let trackHeaderWidth = 80.0
    /// 시퀀스 끝 뒤에 남겨 두는 여백. 끝 근처 클립도 스크롤 없이 끝까지 보이게 한다.
    static let trailingPaddingSeconds = 30.0
}

/// 타임라인에서 일어난 편집 요청. 실제 편집은 상위가 편집기(`ProjectEditor`) 커맨드로 한다.
struct TimelineActions {
    /// 미디어 패널에서 원본(여러 개면 고른 순서대로, #86)을 끌어다 놓았을 때. 트랙은 종류별로 놓은 높이에서 가장 가까운 트랙이고,
    /// 그 종류 트랙이 없으면 빠져 있다(편집기가 첫 트랙을 쓰거나 새로 만든다).
    var dropAssets: ([MediaAsset.ID], [TrackKind: Track.ID], CMTime) -> Void = { _, _, _ in }
    var moveClip: (Clip.ID, Track.ID, CMTime) -> Void = { _, _, _ in }
    var trimClip: (Clip.ID, ClipEdge, CMTime) -> Void = { _, _, _ in }
    /// 롤·슬립·슬라이드 트림(#58).
    var rollClip: (Clip.ID, ClipEdge, CMTime) -> Void = { _, _, _ in }
    var slipClip: (Clip.ID, CMTime) -> Void = { _, _ in }
    var slideClip: (Clip.ID, CMTime) -> Void = { _, _ in }
    /// 두 번째 값이 `true`면 리플 삭제.
    var deleteClips: (Set<Clip.ID>, Bool) -> Void = { _, _ in }
    /// 재생 헤드에서 나눈다. 비어 있으면 재생 헤드에 걸친 모든 클립을 나눈다.
    var splitClips: (Set<Clip.ID>) -> Void = { _ in }
    /// 클립 별칭 입력을 시작한다(#78). 상위가 그 클립을 고르고 인스펙터 이름 칸에 포커스를 준다.
    var renameClip: (Clip.ID) -> Void = { _ in }
    /// 고른 클립 모두의 색상 레이블. `nil`이면 뗀다(#78).
    var setClipColorLabel: (Set<Clip.ID>, ColorLabel?) -> Void = { _, _ in }
    /// 클립 복사·잘라내기·복제와 재생 헤드에 붙여넣기(#62).
    var copyClips: (Set<Clip.ID>) -> Void = { _ in }
    var cutClips: (Set<Clip.ID>) -> Void = { _ in }
    var duplicateClips: (Set<Clip.ID>) -> Void = { _ in }
    /// 클립 하나를 클립 편집 창으로 연다(#81·#85).
    var openClipEditor: (Clip.ID) -> Void = { _ in }
    /// 붙여넣을 것이 없으면 `nil`이라 메뉴를 비활성화한다.
    var paste: (() -> Void)?
    /// 원본을 훑어보기(Quick Look) 창으로 연다.
    var openAsset: (MediaAsset.ID) -> Void = { _ in }
    var revealAsset: (MediaAsset.ID) -> Void = { _ in }
    var switchSequence: (EditSequence.ID) -> Void = { _ in }
    var addSequence: () -> Void = {}
    var renameSequence: (EditSequence.ID, String) -> Void = { _, _ in }
    var deleteSequence: (EditSequence.ID) -> Void = { _ in }
    var addMarker: () -> Void = {}
    var renameMarker: (Marker.ID, String) -> Void = { _, _ in }
    var deleteMarker: (Marker.ID) -> Void = { _ in }
    /// 앞 클립과의 영상 전환. `nil`이면 없앤다(#8).
    var setTransition: (Clip.ID, ClipTransition?) -> Void = { _, _ in }
    /// 재생 헤드에 자막을 둔다.
    var addSubtitle: () -> Void = {}
    var setSubtitleRange: (Subtitle.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var deleteSubtitle: (Subtitle.ID) -> Void = { _ in }
    /// 재생 헤드에 마스크를 둔다(#59).
    var addMask: () -> Void = {}
    var setMaskRange: (Mask.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var deleteMask: (Mask.ID) -> Void = { _ in }
    /// 트랙 전체 음량(0~1)과 음소거.
    var setTrackAudio: (Track.ID, Double, Bool) -> Void = { _, _, _ in }
    var addTrack: (TrackKind) -> Void = { _ in }
    /// 비어 있는 트랙만 지운다.
    var deleteTrack: (Track.ID) -> Void = { _ in }
}

/// 끄는 중인 편집의 미리보기. 손을 떼기 전에 결과(들어갈 자리와 뒤로 밀린 클립)를 보여준다.
private struct DragPreview {
    /// 놓았을 때의 시퀀스. 옮기는 클립·새 클립은 `placeholderID`로 찾는다.
    let sequence: EditSequence
    let placeholderID: Clip.ID
    let trackID: Track.ID
    let time: CMTime
    /// 옮기기·놓기는 들어갈 자리를 점선으로 보여주고, 트림은 클립 자체를 바뀐 길이로 그린다.
    var showsPlaceholder = true
    /// 트림·롤 중이면 클립 안 내용(필름스트립·파형)을 다시 불러오지 않는다(#80). 손을 떼면 한 번 다시 만든다.
    var freezesContent = false
}

/// SwiftUI의 `TimelineView`(일정 주기로 다시 그리는 View)와 이름이 겹치지 않도록 `TimelineEditorView`로 짓는다.
/// 타임라인을 숨겼다 다시 보여도 유지되도록 선택·재생 헤드·배율은 상위(`MainWindowView`)가 소유한다.
struct TimelineEditorView: View {
    let sequence: EditSequence
    /// 시퀀스 메뉴에 보일 프로젝트의 모든 시퀀스.
    var allSequences: [EditSequence] = []
    let assets: [MediaAsset]
    @Binding var selectedClipIDs: Set<Clip.ID>
    @Binding var selectedSubtitleID: Subtitle.ID?
    @Binding var selectedMaskID: Mask.ID?
    @Binding var playheadTime: CMTime
    @Binding var scale: TimelineScale
    /// 끄는 중이면 `true`. 상위가 Esc로 끌기를 취소할지 정하는 데 쓴다.
    @Binding var isDragging: Bool
    /// 값이 바뀌면 끄는 중인 편집을 취소한다(Esc).
    var dragCancelCount = 0
    var actions = TimelineActions()
    @AppStorage(AppPreferences.timelineShowsFilmstripKey) private var showsFilmstrip = true
    @AppStorage(AppPreferences.timelineShowsWaveformKey) private var showsWaveform = true
    @State private var pinchStartScale: TimelineScale?
    @State private var isRenamingSequence = false
    @State private var sequenceNameText = ""
    @State private var isConfirmingSequenceDeletion = false
    /// 이름을 바꾸는 중인 마커.
    @State private var renamingMarkerID: Marker.ID?
    @State private var markerNameText = ""
    @State private var dragPreview: DragPreview?
    /// 타임라인 안에서 끄는 클립과 끈 거리. 원래 행에서 포인터를 따라 반투명하게 그린다.
    @State private var draggedClip: (clip: Clip, translation: CGSize)?
    /// 미디어 패널에서 끌어와 타임라인 위에 있는 원본.
    @State private var hoveringAssetIDs: [MediaAsset.ID] = []
    @State private var isDragCancelled = false

    var body: some View {
        let paddedDuration = sequence.duration + CMTime(seconds: TimelineMetrics.trailingPaddingSeconds, preferredTimescale: standardTimescale)
        let contentWidth = scale.width(for: paddedDuration)
        let pinch = MagnifyGesture()
            .onChanged { value in
                let startScale = pinchStartScale ?? scale
                pinchStartScale = startScale
                scale = startScale.zoomed(byMagnification: value.magnification)
            }
            .onEnded { _ in pinchStartScale = nil }

        VStack(spacing: 0) {
            HStack {
                sequenceMenu
                Spacer()
                markerMenu
                displayMenu
                Button {
                    scale = scale.zoomedOut
                } label: {
                    Label("축소", systemImage: "minus.magnifyingglass")
                }
                .disabled(!scale.canZoomOut)
                .help(ShortcutGuide.zoomOutTimeline.helpText)

                Button {
                    scale = scale.zoomedIn
                } label: {
                    Label("확대", systemImage: "plus.magnifyingglass")
                }
                .disabled(!scale.canZoomIn)
                .help(ShortcutGuide.zoomInTimeline.helpText)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if sequence.tracks.allSatisfy(\.clips.isEmpty), sequence.subtitles.isEmpty, sequence.masks.isEmpty, dragPreview == nil {
                // 빈 타임라인은 "무엇을 하면 되는지"를 안내한다. 원본이 없으면 가져오기부터 안내한다.
                Group {
                    if assets.isEmpty {
                        ContentUnavailableView(
                            "타임라인이 비어 있음",
                            systemImage: "square.and.arrow.down",
                            description: Text("⌘I로 미디어를 가져온 뒤 타임라인에 배치하세요")
                        )
                    } else {
                        ContentUnavailableView(
                            "타임라인이 비어 있음",
                            systemImage: "film.stack",
                            description: Text("미디어 패널에서 원본을 끌어다 놓아 클립을 추가하세요")
                        )
                    }
                }
                // 안내가 남은 높이를 채워야 헤더가 미리보기와의 경계 바로 아래에 붙는다.
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    let assetIDs = items.flatMap(AssetDragPayload.decode)
                    guard !assetIDs.isEmpty else { return false }
                    actions.dropAssets(assetIDs, [:], .zero)
                    return true
                }
            } else {
                timelineContent(contentWidth: contentWidth)
            }
        }
        .simultaneousGesture(pinch)
        .onChange(of: dragCancelCount) {
            // 옮기기·트림은 마우스를 놓을 때 끝나므로, 그때 결과를 반영하지 않도록 표시해 둔다.
            isDragCancelled = dragPreview != nil && hoveringAssetIDs.isEmpty
            clearDrag()
        }
        .alert("마커 이름 변경", isPresented: Binding(
            get: { renamingMarkerID != nil },
            set: {
                if !$0 {
                    renamingMarkerID = nil
                }
            }
        )) {
            TextField("마커 이름", text: $markerNameText)
            Button("변경") {
                if let renamingMarkerID {
                    actions.renameMarker(renamingMarkerID, markerNameText)
                }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("시퀀스 이름 변경", isPresented: $isRenamingSequence) {
            TextField("시퀀스 이름", text: $sequenceNameText)
            Button("변경") { actions.renameSequence(sequence.id, sequenceNameText) }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("\"\(sequence.name)\" 시퀀스를 삭제하시겠습니까?", isPresented: $isConfirmingSequenceDeletion) {
            Button("삭제", role: .destructive) { actions.deleteSequence(sequence.id) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("시퀀스의 클립 배치가 사라집니다. 미디어 패널의 원본은 그대로 남습니다. 실행 취소(⌘Z)로 되돌릴 수 있습니다.")
        }
    }

    /// 타임라인 머리의 시퀀스 이름. 눌러서 시퀀스를 바꾸거나 만들고, 이름을 바꾸거나 지운다.
    private var sequenceMenu: some View {
        Menu {
            ForEach(allSequences) { item in
                Toggle(item.name, isOn: Binding(
                    get: { item.id == sequence.id },
                    set: { isOn in
                        if isOn {
                            actions.switchSequence(item.id)
                        }
                    }
                ))
            }
            Divider()
            Button("새 시퀀스") { actions.addSequence() }
            Button("이름 변경…") {
                sequenceNameText = sequence.name
                isRenamingSequence = true
            }
            // 시퀀스는 최소 하나 있어야 하므로 마지막 남은 시퀀스는 지울 수 없다.
            Button("삭제…", role: .destructive) { isConfirmingSequenceDeletion = true }
                .disabled(allSequences.count <= 1)
        } label: {
            Text(sequence.name)
                .font(.headline)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("시퀀스 — 바꾸기·새로 만들기·이름 변경·삭제")
    }

    /// 마커 목록. 고르면 재생 헤드가 그 마커로 간다.
    private var markerMenu: some View {
        Menu {
            Button(ShortcutGuide.addMarker.title, action: actions.addMarker)
            if !sequence.markers.isEmpty {
                Divider()
                ForEach(sequence.markers) { marker in
                    Button("\(marker.name)  \(Duration.seconds(marker.time.seconds).formatted(.time(pattern: .minuteSecond)))") {
                        playheadTime = marker.time
                    }
                }
            }
        } label: {
            Label("마커", systemImage: "bookmark")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("마커 — 재생 헤드에 마커를 추가(M)하거나 마커로 이동합니다")
    }

    private func beginRenamingMarker(_ marker: Marker) {
        markerNameText = marker.name
        renamingMarkerID = marker.id
    }

    /// 클립 안에 무엇을 그릴지 고른다. 그림이 있는 클립에는 필름스트립을, 소리가 있는 클립에는 파형을 그린다.
    private var displayMenu: some View {
        Menu {
            Toggle(ShortcutGuide.toggleFilmstrip.title, isOn: $showsFilmstrip)
            Toggle(ShortcutGuide.toggleWaveform.title, isOn: $showsWaveform)
        } label: {
            Label("클립 보기", systemImage: "rectangle.split.3x1")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("클립 보기 — 필름스트립·오디오 파형을 켜고 끕니다")
    }

    private func timelineContent(contentWidth: Double) -> some View {
        let shownSequence = dragPreview?.sequence ?? sequence

        return HStack(alignment: .top, spacing: 0) {
            TrackHeaderColumn(tracks: shownSequence.tracks, actions: actions)
            Divider()
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    TimelineRulerView(
                        scale: scale,
                        sequenceDuration: sequence.duration,
                        markers: sequence.markers,
                        playheadTime: $playheadTime,
                        renameMarker: beginRenamingMarker,
                        deleteMarker: actions.deleteMarker
                    )
                    RangeLaneView(
                        items: sequence.subtitles.map { RangeLaneItem(id: $0.id, range: $0.range, title: $0.text.replacingOccurrences(of: "\n", with: " ")) },
                        tint: .teal,
                        sequence: sequence,
                        scale: scale,
                        playheadTime: playheadTime,
                        selectedID: $selectedSubtitleID,
                        addTitle: ShortcutGuide.addSubtitle.title,
                        deleteTitle: "자막 삭제",
                        helpText: "자막 트랙 — 두 번 클릭하거나 우클릭해 재생 헤드에 자막을 추가합니다(T)",
                        add: actions.addSubtitle,
                        setRange: actions.setSubtitleRange,
                        delete: actions.deleteSubtitle
                    )
                    RangeLaneView(
                        items: sequence.masks.map { RangeLaneItem(id: $0.id, range: $0.range, title: $0.effect.title) },
                        tint: .purple,
                        sequence: sequence,
                        scale: scale,
                        playheadTime: playheadTime,
                        selectedID: $selectedMaskID,
                        addTitle: "재생 헤드에 마스크 추가",
                        deleteTitle: "마스크 삭제",
                        helpText: "마스크 트랙 — 두 번 클릭하거나 우클릭해 재생 헤드에 블러·모자이크 마스크를 추가합니다",
                        add: actions.addMask,
                        setRange: actions.setMaskRange,
                        delete: actions.deleteMask
                    )
                    ForEach(shownSequence.tracks) { track in
                        trackRow(track)
                    }
                }
                // 내용이 패널 높이를 채워야 가로 스크롤바가 마지막 트랙 위가 아니라 패널 바닥에 놓인다.
                .frame(width: contentWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(.easeOut(duration: 0.15), value: dragPreview?.time)
                // 놓은 높이로 트랙을, 가로 위치로 시각을 정한다. 트랙 아래 빈 곳에 놓으면 새 트랙을 만든다.
                .contentShape(Rectangle())
                .onDrop(of: [.utf8PlainText, .plainText], delegate: AssetDropDelegate(
                    loadAssetIDs: { hoveringAssetIDs = $0 },
                    update: { location in previewAssetDrop(at: location) },
                    exit: clearDrag,
                    perform: { location in performAssetDrop(at: location) }
                ))
                .overlay(alignment: .topLeading) {
                    PlayheadView()
                        .offset(x: scale.x(for: playheadTime) - 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 원래 시퀀스에서 끄는 클립은 원래 행에 반투명하게 남겨 끌기 제스처를 이어 가고,
    /// 나머지 클립은 미리보기 위치(뒤로 밀린 자리)에 그린다. 들어갈 자리는 강조 테두리로 보여준다.
    private func trackRow(_ track: Track) -> some View {
        let placeholder = dragPreview.flatMap { preview in
            preview.showsPlaceholder && preview.trackID == track.id ? preview.sequence.clip(id: preview.placeholderID) : nil
        }
        var shownTrack = track
        if dragPreview?.showsPlaceholder == true {
            shownTrack.clips.removeAll { $0.id == dragPreview?.placeholderID }
        }
        let ghost = draggedClip.flatMap { dragged in sequence.trackID(containing: dragged.clip.id) == track.id ? dragged : nil }
        // 끄던 클립은 원래 행·자리에 보이지 않게 남겨 둔다. 끌기 제스처가 붙은 뷰가 사라지면 제스처가 끊겨 끌기가 끝나지 않기 때문이다.
        var hiddenClipID: Clip.ID?
        if let ghost, dragPreview?.showsPlaceholder == true {
            hiddenClipID = ghost.clip.id
            shownTrack.clips.append(ghost.clip)
        }

        return TrackRowView(
            track: shownTrack,
            assets: assets,
            scale: scale,
            playheadTime: playheadTime,
            showsFilmstrip: showsFilmstrip,
            showsWaveform: showsWaveform,
            selectedClipIDs: $selectedClipIDs,
            actions: actions,
            ghost: ghost,
            placeholder: placeholder,
            hiddenClipID: hiddenClipID,
            freezesContent: dragPreview?.freezesContent == true,
            dragChanged: { clip, translation in previewClipMove(clip, by: translation) },
            dragEnded: { clip, translation in endClipMove(clip, by: translation) },
            trimChanged: { clip, edge, distance in previewTrim(clip, edge: edge, by: distance) },
            trimEnded: { clip, edge, distance in endTrim(clip, edge: edge, by: distance) },
            dragFinished: finishDrag
        )
    }

    // MARK: - Drag

    /// 끄는 동안 자석처럼 붙인 시작 시각. 클립의 앞뒤 끝이 10pt 안의 클립 경계·재생 헤드·0초에 붙는다.
    private func snappedStart(_ start: CMTime, duration: CMTime, excluding clipID: Clip.ID?) -> CMTime {
        sequence.snappedStart(start, duration: duration, tolerance: scale.time(forX: 10), excluding: clipID, extraEdges: [playheadTime])
    }

    /// 끈 거리만큼 시각을, 트랙 높이 단위로 트랙을 바꾼다. 트랙 밖이나 종류가 다른 트랙으로 끌면 놓을 곳이 없어 `nil`이다.
    private func clipMoveTarget(_ clip: Clip, by translation: CGSize) -> (trackID: Track.ID, time: CMTime)? {
        let rowOffset = Int((translation.height / TimelineMetrics.trackHeight).rounded())
        guard let trackID = sequence.trackID(forMoving: clip.id, byRows: rowOffset) else { return nil }
        let movedStart = scale.time(forX: scale.x(for: clip.timelineStart) + translation.width)
        return (trackID, snappedStart(movedStart, duration: clip.timelineDuration, excluding: clip.id))
    }

    /// 클립 몸통을 끌 때의 편집. ⌘는 슬립, ⇧는 슬라이드, 아니면 옮기기다(#58).
    private enum BodyDragMode {
        case move
        case slip
        case slide
    }

    private var bodyDragMode: BodyDragMode {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            return .slip
        }
        return modifiers.contains(.shift) ? .slide : .move
    }

    /// 끈 거리를 시간으로. ⌥를 누르고 있으면 5분의 1로 줄여 프레임 단위로 맞추기 쉽게 한다.
    private func dragDelta(_ distance: Double) -> CMTime {
        let precision = NSEvent.modifierFlags.contains(.option) ? 0.2 : 1
        return CMTime(seconds: distance * precision / scale.pointsPerSecond, preferredTimescale: standardTimescale)
    }

    private func sourceDuration(of assetID: MediaAsset.ID) -> CMTime? {
        assets.first { $0.id == assetID }?.trimmableDuration
    }

    /// 슬립은 끄는 방향으로 내용이 따라 움직이도록(오른쪽으로 끌면 원본의 더 앞부분이 보이도록) 원본 구간을 반대로 옮긴다.
    private func previewSlipOrSlide(_ clip: Clip, mode: BodyDragMode, distance: Double) {
        guard let trackID = sequence.trackID(containing: clip.id) else { return }
        isDragging = true
        draggedClip = nil
        let delta = dragDelta(distance)
        var preview = sequence
        if mode == .slip {
            preview.slip(clip.id, by: CMTime.zero - delta, sourceDuration: sourceDuration(of:))
        } else {
            preview.slide(clip.id, by: delta, sourceDuration: sourceDuration(of:))
        }
        dragPreview = DragPreview(sequence: preview, placeholderID: clip.id, trackID: trackID, time: delta, showsPlaceholder: false)
    }

    private func previewClipMove(_ clip: Clip, by translation: CGSize) {
        guard !isDragCancelled else { return }
        let mode = bodyDragMode
        guard mode == .move else {
            previewSlipOrSlide(clip, mode: mode, distance: translation.width)
            return
        }
        isDragging = true
        draggedClip = (clip, translation)
        // 놓을 곳이 없으면 미리보기를 거둬 클립이 원래 자리에 보이게 한다(놓으면 아무것도 바뀌지 않는다).
        guard let target = clipMoveTarget(clip, by: translation) else {
            dragPreview = nil
            return
        }
        // 놓을 트랙·시각이 그대로면 미리보기를 다시 만들지 않는다(마우스가 움직일 때마다 클립 내용을 다시 그리지 않기 위함).
        guard dragPreview?.trackID != target.trackID || dragPreview?.time != target.time else { return }
        var preview = sequence
        preview.moveClip(clip.id, toTrack: target.trackID, at: target.time)
        dragPreview = DragPreview(sequence: preview, placeholderID: clip.id, trackID: target.trackID, time: target.time)
    }

    private func endClipMove(_ clip: Clip, by translation: CGSize) {
        defer {
            isDragCancelled = false
            clearDrag()
        }
        guard !isDragCancelled else { return }
        switch bodyDragMode {
        case .slip:
            actions.slipClip(clip.id, CMTime.zero - dragDelta(translation.width))
        case .slide:
            actions.slideClip(clip.id, dragDelta(translation.width))
        case .move:
            if let target = clipMoveTarget(clip, by: translation) {
                actions.moveClip(clip.id, target.trackID, target.time)
            }
        }
    }

    /// 끈 거리를 트림할 시간으로 바꾼다. ⌥를 누르고 있으면 5분의 1로 줄여 프레임 단위로 맞추기 쉽게 하고,
    /// 뒤 끝은 다른 클립 경계·재생 헤드에 붙인다(앞 끝은 리플 트림이라 클립 시작 위치가 그대로라 붙이지 않는다).
    private func trimDelta(_ clip: Clip, edge: ClipEdge, distance: Double) -> CMTime {
        let precision = NSEvent.modifierFlags.contains(.option) ? 0.2 : 1
        let delta = CMTime(seconds: distance * precision / scale.pointsPerSecond, preferredTimescale: standardTimescale)
        guard edge == .end else { return delta }
        let movedEnd = clip.timelineRange.end + delta
        return snappedStart(movedEnd, duration: .zero, excluding: clip.id) - clip.timelineRange.end
    }

    private func previewTrim(_ clip: Clip, edge: ClipEdge, by distance: Double) {
        guard !isDragCancelled, let trackID = sequence.trackID(containing: clip.id) else { return }
        isDragging = true
        // ⌘를 누르고 끌면 맞닿은 이웃과의 경계를 옮기는 롤 트림이다(#58).
        if NSEvent.modifierFlags.contains(.command) {
            var preview = sequence
            preview.roll(clip.id, edge: edge, by: dragDelta(distance), sourceDuration: sourceDuration(of:))
            dragPreview = DragPreview(sequence: preview, placeholderID: clip.id, trackID: trackID, time: dragDelta(distance), showsPlaceholder: false, freezesContent: true)
            return
        }
        let sourceDuration = assets.first { $0.id == clip.assetID }?.trimmableDuration
        let range = clip.trimmedSourceRange(edge: edge, by: trimDelta(clip, edge: edge, distance: distance), sourceDuration: sourceDuration)
        guard dragPreview?.time != range.duration || dragPreview?.sequence.clip(id: clip.id)?.sourceRange != range else { return }
        // 끄는 동안은 잡은 끝만 마우스를 따라가고 나머지와 뒤 클립은 제자리에 둔다. 리플은 손을 뗄 때 반영한다(#80).
        var preview = sequence
        preview.updateClips([clip.id]) { $0 = $0.trimDisplay(edge: edge, sourceRange: range) }
        dragPreview = DragPreview(sequence: preview, placeholderID: clip.id, trackID: trackID, time: range.duration, showsPlaceholder: false, freezesContent: true)
    }

    private func endTrim(_ clip: Clip, edge: ClipEdge, by distance: Double) {
        defer {
            isDragCancelled = false
            clearDrag()
        }
        guard !isDragCancelled else { return }
        if NSEvent.modifierFlags.contains(.command) {
            actions.rollClip(clip.id, edge, dragDelta(distance))
        } else {
            actions.trimClip(clip.id, edge, trimDelta(clip, edge: edge, distance: distance))
        }
    }

    /// 놓을 트랙과 시각. 원본 종류마다 놓은 높이에서 가장 가까운 같은 종류의 트랙에 넣고, 새 트랙은 만들지 않는다(트랙 머리 우클릭으로 직접 만든다).
    /// 그 종류 트랙이 하나도 없으면 빠진다(편집기가 그때만 새로 만든다). 시각은 첫 원본 길이로 경계에 붙인다.
    /// 행 위치는 미리보기가 아닌 원래 시퀀스 기준이라 미리보기가 위치 판단을 바꾸지 않는다.
    private func assetDropTarget(at location: CGPoint, assets dropped: [MediaAsset]) -> (trackIDs: [TrackKind: Track.ID], time: CMTime) {
        let rowIndex = Int(((location.y - TimelineMetrics.rulerHeight - TimelineMetrics.rangeLaneHeight * 2) / TimelineMetrics.trackHeight).rounded(.down))
        var trackIDs: [TrackKind: Track.ID] = [:]
        for kind in Set(dropped.map(\.trackKind)) {
            trackIDs[kind] = sequence.nearestTrackID(kind: kind, toRow: rowIndex)
        }
        let firstDuration = dropped.first?.placementDuration ?? .zero
        return (trackIDs, snappedStart(scale.time(forX: location.x), duration: firstDuration, excluding: nil))
    }

    /// 끄는 원본들(고른 순서).
    private var hoveringAssets: [MediaAsset] {
        hoveringAssetIDs.compactMap { id in assets.first { $0.id == id } }
    }

    /// 놓았을 때와 같은 결과(고른 순서대로 이어 붙이고 뒤 클립을 민 모습)를 미리 보여준다.
    private func previewAssetDrop(at location: CGPoint) {
        let dropped = hoveringAssets
        guard let first = dropped.first else { return }
        let target = assetDropTarget(at: location, assets: dropped)
        if let dragPreview, target.trackIDs[first.trackKind] == nil || dragPreview.trackID == target.trackIDs[first.trackKind], dragPreview.time == target.time {
            return
        }
        var preview = sequence
        var trackIDs = target.trackIDs
        for kind in Set(dropped.map(\.trackKind)) where trackIDs[kind] == nil {
            trackIDs[kind] = preview.addTrack(kind: kind)
        }
        let clips = dropped.compactMap { asset in asset.makeClip(at: target.time).map { (clip: $0, kind: asset.trackKind) } }
        guard let firstClipID = preview.placeInOrder(clips, trackIDs: trackIDs).first, let firstTrackID = trackIDs[first.trackKind] else { return }
        isDragging = true
        dragPreview = DragPreview(sequence: preview, placeholderID: firstClipID, trackID: firstTrackID, time: target.time)
    }

    private func performAssetDrop(at location: CGPoint) -> Bool {
        defer { clearDrag() }
        let dropped = hoveringAssets
        guard !dropped.isEmpty else { return false }
        let target = assetDropTarget(at: location, assets: dropped)
        actions.dropAssets(dropped.map(\.id), target.trackIDs, target.time)
        return true
    }

    /// 끌기 제스처가 끝났거나 중간에 끊겼을 때(놓기 처리가 불리지 않는 경우 포함) 미리보기를 거둬 원래대로 돌린다.
    /// 놓기 처리가 먼저 끝나도록 한 박자 뒤에 정리한다.
    private func finishDrag() {
        DispatchQueue.main.async {
            guard hoveringAssetIDs.isEmpty else { return }
            isDragCancelled = false
            clearDrag()
        }
    }

    private func clearDrag() {
        dragPreview = nil
        draggedClip = nil
        hoveringAssetIDs = []
        isDragging = false
    }
}

/// 미디어 패널에서 끌어온 원본(문자열로 된 원본 ID)을 받는다. 끄는 동안 위치를 알려 들어갈 자리를 미리 보여준다.
private struct AssetDropDelegate: DropDelegate {
    /// 끄는 원본들(고른 순서, #86).
    let loadAssetIDs: ([MediaAsset.ID]) -> Void
    let update: (CGPoint) -> Void
    let exit: () -> Void
    let perform: (CGPoint) -> Bool

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.utf8PlainText, .plainText]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String else { return }
            let assetIDs = AssetDragPayload.decode(text)
            guard !assetIDs.isEmpty else { return }
            DispatchQueue.main.async {
                loadAssetIDs(assetIDs)
                update(info.location)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info _: DropInfo) {
        exit()
    }

    func performDrop(info: DropInfo) -> Bool {
        perform(info.location)
    }
}

/// 트랙 이름 열. 우클릭으로 트랙을 직접 추가하거나 빈 트랙을 지운다(놓기로는 새 트랙을 만들지 않는다).
private struct TrackHeaderColumn: View {
    let tracks: [Track]
    let actions: TimelineActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: TimelineMetrics.rulerHeight)
            Label("자막", systemImage: "captions.bubble")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimelineMetrics.rangeLaneHeight)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(ShortcutGuide.addSubtitle.title, action: actions.addSubtitle)
                }
            Label("마스크", systemImage: "square.dashed")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimelineMetrics.rangeLaneHeight)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("재생 헤드에 마스크 추가", action: actions.addMask)
                }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                // 같은 종류 트랙끼리 1부터 번호를 매긴다. 영상은 프리미어처럼 맨 아래(메인)가 1이고 위로 갈수록 커지며,
                // 오디오는 위에서부터 1이다.
                let number = track.kind == .video
                    ? tracks[index...].filter { $0.kind == .video }.count
                    : tracks[...index].filter { $0.kind == .audio }.count

                HStack(spacing: 2) {
                    Label("\(track.kind.title) \(number)", systemImage: track.kind.symbolName)
                        .font(.caption)
                    Spacer(minLength: 0)
                    // 트랙 전체 소리를 끄고 켠다(결과물에 반영).
                    Button {
                        actions.setTrackAudio(track.id, track.volume, !track.isMuted)
                    } label: {
                        Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                            .font(.caption2)
                            .foregroundStyle(track.isMuted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .help(track.isMuted ? "트랙 음소거 해제" : "트랙 음소거 — 이 트랙의 소리를 결과물에서 뺍니다")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimelineMetrics.trackHeight)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .contextMenu {
                    addTrackButtons
                    Divider()
                    Menu("트랙 음량") {
                        ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { volume in
                            Toggle(volume.formatted(.percent), isOn: Binding(
                                get: { abs(track.volume - volume) < 0.001 },
                                set: { _ in actions.setTrackAudio(track.id, volume, track.isMuted) }
                            ))
                        }
                    }
                    Divider()
                    // 클립이 있는 트랙을 지우면 편집 내용을 잃기 쉬워 빈 트랙만 지운다.
                    Button("트랙 삭제") { actions.deleteTrack(track.id) }
                        .disabled(!track.clips.isEmpty)
                }
            }
            // 트랙 아래 빈 곳에서도 트랙을 추가할 수 있다.
            Color.clear
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .contextMenu { addTrackButtons }
        }
        .frame(width: TimelineMetrics.trackHeaderWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .help("트랙 — 우클릭해 영상·오디오 트랙을 추가하거나 빈 트랙을 지웁니다")
    }

    @ViewBuilder
    private var addTrackButtons: some View {
        Button("영상 트랙 추가") { actions.addTrack(.video) }
        Button("오디오 트랙 추가") { actions.addTrack(.audio) }
    }
}

#Preview("빈 타임라인 — 원본 있음") {
    @Previewable @State var selectedClipIDs: Set<Clip.ID> = []
    @Previewable @State var playheadTime = CMTime.zero
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: EditSequence(id: UUID(), name: "시퀀스 1", tracks: []),
        assets: SampleData.project.assets,
        selectedClipIDs: $selectedClipIDs,
        selectedSubtitleID: .constant(nil),
        selectedMaskID: .constant(nil),
        playheadTime: $playheadTime,
        scale: $scale,
        isDragging: .constant(false)
    )
    .frame(width: 700, height: 240)
}

#Preview("빈 타임라인 — 원본 없음") {
    @Previewable @State var selectedClipIDs: Set<Clip.ID> = []
    @Previewable @State var playheadTime = CMTime.zero
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: EditSequence(id: UUID(), name: "시퀀스 1", tracks: []),
        assets: [],
        selectedClipIDs: $selectedClipIDs,
        selectedSubtitleID: .constant(nil),
        selectedMaskID: .constant(nil),
        playheadTime: $playheadTime,
        scale: $scale,
        isDragging: .constant(false)
    )
    .frame(width: 700, height: 240)
}

#Preview("샘플 시퀀스") {
    @Previewable @State var selectedClipIDs: Set<Clip.ID> = []
    @Previewable @State var playheadTime = CMTime(seconds: 5, preferredTimescale: standardTimescale)
    @Previewable @State var scale = TimelineScale(pointsPerSecond: 40)

    TimelineEditorView(
        sequence: SampleData.mainSequence,
        assets: SampleData.project.assets,
        selectedClipIDs: $selectedClipIDs,
        selectedSubtitleID: .constant(nil),
        selectedMaskID: .constant(nil),
        playheadTime: $playheadTime,
        scale: $scale,
        isDragging: .constant(false)
    )
    .frame(width: 700, height: 240)
}
