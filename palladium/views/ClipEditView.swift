import AppKit
import AVFoundation
import CoreMedia
import Observation
import SwiftUI

/// 클립 편집 창에서 열 대상(#81, #85). 미디어 패널에서 열면 항목(원본은 바꾸지 않고 파생 항목을 만든다), 타임라인에서 열면 클립 하나를 바꾼다.
enum ClipEditTarget: Hashable {
    case asset(MediaAsset.ID)
    case clip(Clip.ID)
}

/// 클립 편집 창을 여는 값. 프로젝트마다 창 하나다(같은 값으로 열면 이미 열린 창이 앞으로 온다).
struct ClipEditWindowValue: Codable, Hashable {
    let projectID: Project.ID
}

/// 프로젝트 창과 그 클립 편집 창을 잇는다(#85). 프로젝트 창이 만들고, 클립 편집 창은 프로젝트 ID로 찾는다.
/// 편집은 프로젝트 창의 편집기 커맨드로 해 실행 취소가 프로젝트 창 기록에 남는다.
@Observable
final class ClipEditSession {
    let editor: ProjectEditor
    /// 창에 보일 대상.
    var target: ClipEditTarget?
    /// 대상을 새로 열 때마다 바뀐다. 창은 이 값이 바뀌면 고치던 값을 버리고 새 대상으로 맞춘다(자르기로 대상이 바뀔 때는 그대로).
    private(set) var openID = UUID()
    /// 적용하지 않은 변경이 있을 때 다른 대상으로 열려고 하면 여기 두고, 창이 버릴지 묻는다.
    var pendingTarget: ClipEditTarget?
    /// 창에 보일 탭. ⌘T는 트림 탭으로, 인스펙터의 "클립 편집 열기…"는 크롭 탭으로 연다(#90).
    var tab = ClipEditTab.trim
    /// `pendingTarget`을 열 때 보일 탭.
    private var pendingTab = ClipEditTab.trim
    /// 창에 적용하지 않은 변경이 있는지. 창이 알려 준다.
    var hasUnappliedChanges = false
    /// 창이 열려 있는지. 창이 알려 준다.
    var isWindowOpen = false
    /// 적용하지 않은 채 창을 닫을 때의 확인 문구. 창이 대상에 맞춰 알려 준다.
    var closePrompt = UnsavedChangesPrompt(message: "")
    /// 닫기 확인에서 "적용"(원본 항목이면 "새 항목으로 저장")을 고르면 창의 기본 버튼과 같은 일을 한다. 창이 넣어 준다.
    var applyChanges: () -> Void = {}
    /// 파일 > ⌘S(#92). 적용하되 창은 열어 둔다. 창이 넣어 준다.
    var saveFromMenu: () -> Void = {}
    /// ⌘S로 적용한 뒤 창 위쪽에 잠깐 띄우는 알림(#96). 원본 항목에서 새 항목으로 바뀌어 창 내용이 새로 그려져도 남도록 여기 둔다.
    var toast: ToastMessage?

    /// 클립 편집 창이 앞에 있을 때 ⌘S 자리의 항목. 이름은 닫기 확인의 기본 버튼과 같다("적용"·"새 항목으로 저장").
    /// 적용하지 않은 변경이 없으면 `nil`이라 메뉴가 꺼진다.
    var saveCommand: SaveCommand? {
        guard hasUnappliedChanges else { return nil }
        let title = closePrompt.saveTitle
        return SaveCommand(title: title) { [self] in
            saveFromMenu()
            toast = ToastMessage(text: SaveCommand(title: title, perform: {}).doneMessage)
        }
    }

    init(editor: ProjectEditor) {
        self.editor = editor
    }

    /// `newTarget`을 `tab` 탭으로 연다. 창에 같은 대상이 열려 있으면 고치던 값은 그대로 두고 탭만 바꾸며,
    /// 다른 대상을 고치던 중이면 창이 먼저 묻는다.
    func open(_ newTarget: ClipEditTarget, tab: ClipEditTab = .trim) {
        guard isWindowOpen else { return show(newTarget, tab: tab) }
        if newTarget == target {
            pendingTarget = nil
            self.tab = tab
        } else if hasUnappliedChanges {
            pendingTarget = newTarget
            pendingTab = tab
        } else {
            show(newTarget, tab: tab)
        }
    }

    /// 다른 대상을 열지 묻는 창의 답. `applying`이면 고친 내용을 먼저 적용(원본 항목은 새 항목으로 저장)하고 연다.
    /// 취소는 `pendingTarget`을 비우기만 한다(고치던 대상과 변경은 그대로).
    func resolvePendingTarget(applying: Bool) {
        guard let pendingTarget else { return }
        if applying {
            applyChanges()
        }
        show(pendingTarget, tab: pendingTab)
    }

    /// 고치던 값을 버리고 `newTarget`을 `tab` 탭으로 연다.
    func show(_ newTarget: ClipEditTarget, tab: ClipEditTab = .trim) {
        target = newTarget
        self.tab = tab
        pendingTarget = nil
        hasUnappliedChanges = false
        openID = UUID()
    }
}

/// 열린 프로젝트마다의 클립 편집 연결.
@Observable
final class ClipEditSessions {
    static let shared = ClipEditSessions()
    private(set) var sessions: [Project.ID: ClipEditSession] = [:]

    func session(for editor: ProjectEditor) -> ClipEditSession {
        if let session = sessions[editor.project.id], session.editor === editor {
            return session
        }
        let session = ClipEditSession(editor: editor)
        sessions[editor.project.id] = session
        return session
    }

    func remove(_ projectID: Project.ID) {
        sessions[projectID] = nil
    }
}

/// 클립 편집 창(#85). 크기 조절·이동·최대화·최소화가 되는 별도 창이다. 프로젝트 창이 닫히면 함께 닫힌다.
struct ClipEditWindowView: View {
    let value: ClipEditWindowValue?

    var body: some View {
        let session = value.flatMap { ClipEditSessions.shared.sessions[$0.projectID] }
        // 닫기 버튼의 변경 표시(점)가 바로 바뀌도록 이 값을 읽어 둔다(확인 장치는 닫는 순간 다시 읽는다).
        let _ = session?.hasUnappliedChanges
        // `Group`에 붙인 수정자는 안쪽 화면마다 따로 붙어, 대상이 바뀔 때마다 창 열림 표시가 꺼지고(#91)
        // 닫기 확인 장치가 새로 붙어 서로를 원래 delegate로 삼다 멈췄다. 대상이 바뀌어도 그대로인 `ZStack`에 단다.
        ZStack {
            if let session, let target = session.target {
                ClipEditView(session: session, target: target)
                    .id(session.openID)
            } else {
                ContentUnavailableView("대상이 없습니다", systemImage: "film", description: Text("프로젝트 창에서 클립을 두 번 누르거나 ⌘T로 여세요"))
                    .frame(minWidth: 480, minHeight: 320)
                    .navigationTitle("클립 편집")
            }
        }
        // ⌘S로 적용하면 "적용됨"을 잠깐 띄운다(#96).
        .toast(Binding(get: { session?.toast }, set: { session?.toast = $0 }))
        // 클립 편집 창이 앞에 있으면 ⌘S는 프로젝트 저장이 아니라 적용이다(#92).
        .focusedSceneValue(\.saveCommand, session?.saveCommand)
        .onAppear { session?.isWindowOpen = true }
        .onDisappear { session?.isWindowOpen = false }
        // 적용하지 않은 채 닫으면(닫기 버튼·⌘W·앱 종료·프로젝트 창 닫기) 묻는다. 창이 살아 있는 동안 바뀌지 않는 이 뷰에 둔다.
        .background {
            UnsavedChangesGuard(
                hasUnsavedChanges: { session?.hasUnappliedChanges ?? false },
                prompt: session?.closePrompt ?? UnsavedChangesPrompt(message: ""),
                role: .attached(to: value?.projectID ?? UUID()),
                save: {
                    session?.applyChanges()
                    return true
                },
                discardChanges: { session?.hasUnappliedChanges = false }
            )
        }
    }
}

/// 클립 편집 창의 탭.
enum ClipEditTab {
    /// 시간 자르기(#81).
    case trim
    /// 화면 자르기(#85).
    case crop
}

/// 대상이 가진(또는 창에서 고치는) 구간·뺀 구간(#99)·크롭.
private struct ClipEditValues: Equatable {
    var range: CMTimeRange
    var excluded: [CMTimeRange] = []
    var crop: ClipCrop
}

/// QuickTime의 다듬기처럼 영상·오디오 하나를 원본 전체와 함께 보며 구간을 고르고 자르고(트림 탭, #81), 영상 화면을 잘라낸다(크롭 탭, #85).
/// 미리보기의 굳은 결정("시퀀스만 재생")의 예외로, 이 창에서만 원본 구간을 재생한다. 원본 파일은 바꾸지 않는다.
/// 고르는 동안은 창 안에서만 바뀌고, "적용"·"새 항목으로 저장"이나 "자르기"를 눌러야 프로젝트가 바뀐다. 원본 항목은 "적용"할 수 없다.
/// 대상이 바깥(실행 취소·인스펙터 등)에서 바뀌면 고치던 값을 버리고 대상에 다시 맞춘다.
struct ClipEditView: View {
    let session: ClipEditSession
    @State private var kind: ClipEditTarget
    @State private var range: CMTimeRange
    /// 뺀 구간들(#99). 결과는 손잡이 구간에서 이 구간들을 빼고 남은 구간들을 이어 붙인 것이다.
    @State private var excluded: [CMTimeRange]
    /// "구간 빼기"·"되살리기" 뒤 손잡이가 돌아갈 바깥 구간. 창을 열거나 적용한 때의 구간이다.
    @State private var outer: CMTimeRange
    /// 눌러 고른 뺀 구간(되살리기 대상).
    @State private var selectedExcluded: CMTimeRange?
    @State private var crop: ClipCrop
    /// 대상이 마지막으로 가진 값. 고치는 값과 다르면 적용하지 않은 변경이 있다.
    @State private var committed: ClipEditValues?
    @State private var cropAspect = CropAspect.free
    /// 원본 화면 크기(회전 반영). 크롭 테두리와 비율 계산에 쓴다.
    @State private var contentSize: CGSize?
    /// 방향키가 옮기는 손잡이. 마지막으로 잡은 쪽이다.
    @State private var activeEdge = ClipEdge.end
    @State private var player: TrimPlayer?
    /// 필름스트립 막대 배율과 스크롤(#97). 트림·크롭 탭이 함께 쓴다.
    @State private var barZoom = TrimBarZoom()
    @State private var barScrollPosition = ScrollPosition(x: 0)
    @State private var barViewport = TrimBarViewport()
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    /// 시간 글자(분:초.소수 첫째 자리)를 만드는 데만 쓴다.
    private let labelScale = TimelineScale(pointsPerSecond: 40)

    init(session: ClipEditSession, target: ClipEditTarget) {
        self.session = session
        let values = Self.currentValues(of: target, in: session.editor)
        _kind = State(initialValue: target)
        _range = State(initialValue: values?.range ?? CMTimeRange(start: .zero, duration: .zero))
        _excluded = State(initialValue: values?.excluded ?? [])
        _outer = State(initialValue: values?.range ?? CMTimeRange(start: .zero, duration: .zero))
        _crop = State(initialValue: values?.crop ?? ClipCrop())
        _committed = State(initialValue: values)
    }

    private var editor: ProjectEditor {
        session.editor
    }

    var body: some View {
        let isAskingToSwitch = Binding<Bool>(
            get: { session.pendingTarget != nil },
            set: {
                if !$0 {
                    session.pendingTarget = nil
                }
            }
        )

        VStack(alignment: .leading, spacing: 12) {
            if let asset {
                if asset.kind == .video {
                    Picker("", selection: Binding(get: { session.tab }, set: { session.tab = $0 })) {
                        Text("트림").tag(ClipEditTab.trim)
                        Text("크롭").tag(ClipEditTab.crop)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                }
                picture(for: asset)
                if isCropping(asset) {
                    cropControls
                }
                // 재생 버튼·재생 위치 막대·시간 요약은 두 탭 모두에 둔다(#89). 크롭 탭에서는 구간 손잡이를 감춘다.
                HStack(spacing: 12) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                            .frame(width: 20)
                    }
                    .help("고른 구간 재생/일시정지 (Space)")
                    TrimBarView(
                        asset: asset,
                        range: range,
                        excluded: excluded,
                        selectedExcluded: selectedExcluded,
                        playhead: player?.currentTime ?? range.start,
                        activeEdge: activeEdge,
                        allowsRangeEditing: !isCropping(asset),
                        canExclude: canExclude,
                        selectExcluded: { selectedExcluded = $0 },
                        excludeSelection: excludeSelection,
                        restore: { restore($0) },
                        zoom: barZoom,
                        scrollPosition: $barScrollPosition,
                        viewport: $barViewport,
                        setZoom: setBarZoom,
                        beginScrubbing: { player?.beginScrubbing() },
                        moveEdge: moveEdge,
                        scrub: { player?.seek(to: $0) }
                    )
                    zoomButtons(for: asset)
                }
                timeSummary(for: asset)
                actions(for: asset)
            } else {
                ContentUnavailableView("대상이 없습니다", systemImage: "scissors", description: Text("원본이나 클립이 지워졌습니다"))
                Button("닫기") { close() }
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 540)
        .navigationTitle(windowTitle)
        // 이 창이 앞에 있으면 보기 메뉴의 확대·축소는 필름스트립 막대가 대상이다(#97).
        .focusedSceneValue(\.zoomCommand, barZoomCommand)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .space, .delete, .deleteForward]) { press in
            handle(press)
        }
        .task(id: asset?.mediaKey) {
            guard let asset else { return }
            player = TrimPlayer(url: ProxyGenerator.previewURL(for: asset))
            player?.seek(to: range.start)
            isFocused = true
            contentSize = await ClipContentProvider.shared.contentSize(for: asset)
        }
        .onDisappear { player?.stop() }
        // 대상이 바깥에서 바뀌면(실행 취소·인스펙터·자르기) 고치던 값을 버리고 다시 맞춘다.
        .onChange(of: Self.currentValues(of: kind, in: editor)) { _, values in
            committed = values
            if let values {
                reset(to: values)
            }
        }
        .onChange(of: hasUnappliedChanges, initial: true) { _, hasChanges in
            session.hasUnappliedChanges = hasChanges
        }
        .onChange(of: closePrompt.message + closePrompt.saveTitle, initial: true) {
            session.closePrompt = closePrompt
            session.applyChanges = { applyDefault() }
            session.saveFromMenu = { saveKeepingWindow() }
        }
        // 닫기 확인과 같은 문구·버튼으로 묻는다(앱 공통 규칙, #91).
        .alert(closePrompt.message, isPresented: isAskingToSwitch) {
            Button("\(closePrompt.saveTitle)하고 열기") { session.resolvePendingTarget(applying: true) }
            Button(closePrompt.discardTitle, role: .destructive) { session.resolvePendingTarget(applying: false) }
            Button("취소", role: .cancel) { session.pendingTarget = nil }
        } message: {
            Text("다른 대상을 열기 전에 정하세요. \(closePrompt.information)")
        }
    }

    // MARK: - Parts

    private func picture(for asset: MediaAsset) -> some View {
        Group {
            if asset.kind == .video, let player {
                PlayerSurfaceView(player: player.player)
                    .overlay {
                        if session.tab == .crop, let contentSize {
                            CropOverlayView(crop: $crop, contentSize: contentSize, aspect: cropAspect)
                        }
                    }
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func timeSummary(for asset: MediaAsset) -> some View {
        HStack {
            if isCropping(asset) {
                Text("재생 위치 \(labelScale.timeLabel(for: player?.currentTime ?? range.start)) · 구간 \(labelScale.timeLabel(for: range.start))–\(labelScale.timeLabel(for: range.end))")
                    .monospacedDigit()
                Spacer()
                Text("막대를 눌러 다른 장면으로 옮깁니다. 구간은 트림 탭에서 바꿉니다")
                    .foregroundStyle(.secondary)
            } else {
                Text(trimSummary)
                    .monospacedDigit()
                Spacer()
                Text("↑/↓ \(activeEdge == .start ? "시작" : "끝")을 0.1초씩, ⇧와 함께 1초씩 · ⌥ 끌기로 정밀하게")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    /// 크롭 탭을 보고 있는지. 크롭은 영상에만 있다.
    private func isCropping(_ asset: MediaAsset) -> Bool {
        session.tab == .crop && asset.kind == .video
    }

    /// 막대 확대·축소·전체 맞춤 버튼(#97). 보기 메뉴(⌘=/⌘-/⌘0)와 같은 동작이다.
    private func zoomButtons(for asset: MediaAsset) -> some View {
        HStack(spacing: 2) {
            Button {
                zoomBar(by: 1 / TrimBarZoom.stepFactor)
            } label: {
                Label("축소", systemImage: "minus.magnifyingglass")
            }
            .disabled(!barZoom.canZoomOut)
            .help(ShortcutGuide.zoomOutTrimBar.helpText)
            Button {
                zoomBar(by: TrimBarZoom.stepFactor)
            } label: {
                Label("확대", systemImage: "plus.magnifyingglass")
            }
            .disabled(!barZoom.canZoomIn(duration: asset.duration, visibleWidth: barViewport.visibleWidth))
            .help(ShortcutGuide.zoomInTrimBar.helpText)
            Button {
                setBarZoom(TrimBarZoom())
            } label: {
                Label("전체 맞춤", systemImage: "arrow.left.and.right")
            }
            .disabled(barZoom.isFit)
            .help(ShortcutGuide.fitTrimBar.helpText)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    /// 비율 프리셋, 위·아래·왼쪽·오른쪽 자르기 값(%), 초기화.
    private var cropControls: some View {
        HStack(spacing: 12) {
            Picker("비율", selection: $cropAspect) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .fixedSize()
            .disabled(contentSize == nil)
            .help("고른 비율로 맞추고, 끄는 동안에도 그 비율을 지킵니다. 자유에서는 ⇧를 누른 채 끌면 지금 비율을 지킵니다")
            .onChange(of: cropAspect) { _, aspect in
                if let contentSize, let ratio = aspect.ratio(contentSize: contentSize) {
                    crop = crop.fitted(toAspectRatio: ratio, contentSize: contentSize)
                }
            }
            Spacer()
            cropField("위", value: \.top)
            cropField("아래", value: \.bottom)
            cropField("왼쪽", value: \.left)
            cropField("오른쪽", value: \.right)
            Button("초기화") {
                crop = ClipCrop()
                cropAspect = .free
            }
            .disabled(crop.isDefault)
            .help("자르지 않은 원래 화면으로 되돌립니다")
        }
        .font(.callout)
    }

    /// 원본 화면 대비 자를 비율(%)을 숫자로 넣는다. 넣으면 비율 프리셋은 자유로 돌아간다.
    private func cropField(_ title: String, value keyPath: WritableKeyPath<ClipCrop, Double>) -> some View {
        let binding = Binding<Double>(
            get: { crop[keyPath: keyPath] * 100 },
            set: { percent in
                crop = crop.setting(keyPath, to: percent / 100)
                cropAspect = .free
            }
        )
        return HStack(spacing: 4) {
            Text(title)
            TextField(title, value: binding, format: .number.precision(.fractionLength(0 ... 1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Text("%")
                .foregroundStyle(.secondary)
        }
        .help("\(title)에서 자를 만큼(원본 화면 대비 %)")
    }

    @ViewBuilder
    private func actions(for asset: MediaAsset) -> some View {
        let playhead = player?.currentTime ?? range.start
        HStack {
            if session.tab == .trim || asset.kind != .video {
                Button("자르기") { split(at: playhead) }
                    .disabled(!TrimRange.canSplit(range, at: playhead) || !excluded.isEmpty)
                    .help(excluded.isEmpty ? "재생 위치에서 둘로 자릅니다. 옮겨 둔 손잡이 구간과 크롭도 함께 반영합니다" : "뺀 구간이 있으면 자를 수 없습니다. 먼저 적용하거나 되살리세요")
                Button("구간 빼기") { excludeSelection() }
                    .disabled(!canExclude)
                    .help(ShortcutGuide.excludeRange.helpText)
                Button("되살리기") { restore() }
                    .disabled(selectedExcluded == nil)
                    .help("빗금 친 뺀 구간을 눌러 고른 뒤 다시 포함합니다")
            }
            Spacer()
            // "취소"는 버리겠다는 뜻이라 묻지 않고 닫는다.
            Button("취소", role: .cancel) { close() }
                .keyboardShortcut(.cancelAction)
            switch kind {
            case .asset:
                // 원본 항목은 바꾸지 않는다. 파생 항목만 자기 구간·크롭을 "적용"으로 바꿀 수 있다.
                if asset.isDerived {
                    Button("새 항목으로 저장") { saveAsNewItem(asset) }
                        .help("이 구간·크롭으로 파생 항목을 하나 더 미디어 패널에 추가합니다(파일은 복사하지 않음)")
                    Button("적용") {
                        applyDefault()
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("이 파생 항목이 쓰는 구간·크롭을 바꿉니다")
                } else {
                    Button("새 항목으로 저장") {
                        applyDefault()
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("이 구간·크롭으로 파생 항목을 미디어 패널에 추가합니다. 원본 항목·파일은 그대로입니다")
                }
            case let .clip(clipID):
                Button("적용") {
                    applyDefault()
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Model

    private var asset: MediaAsset? {
        switch kind {
        case let .asset(assetID): editor.asset(id: assetID)
        case let .clip(clipID): editor.currentSequence.clip(id: clipID).flatMap { editor.asset(id: $0.assetID) }
        }
    }

    private var hasUnappliedChanges: Bool {
        committed.map { $0 != ClipEditValues(range: range, excluded: excluded, crop: crop) } ?? false
    }

    /// 손잡이 구간에서 뺀 구간을 빼고 남은 구간들(#99). 재생·적용·저장이 이 구간들을 쓴다.
    private var keptRanges: [CMTimeRange] {
        RangeExclusion.kept(bounds: range, excluded: excluded)
    }

    /// 지금 손잡이 구간을 뺄 수 있는지. 바깥 구간 전체를 고른 채이거나 빼면 남는 구간이 없으면 뺄 수 없다.
    private var canExclude: Bool {
        guard let asset, !isCropping(asset), range != outer else { return false }
        return !RangeExclusion.kept(bounds: outer, excluded: excluded + [range]).isEmpty
    }

    /// "시작 0:02.0 · 끝 0:12.0 · 길이 0:10.0", 뺀 구간이 있으면 "· 구간 3개 · 남은 길이 0:07.0"을 붙인다.
    private var trimSummary: String {
        let base = "시작 \(labelScale.timeLabel(for: range.start)) · 끝 \(labelScale.timeLabel(for: range.end)) · 길이 \(labelScale.timeLabel(for: range.duration))"
        guard !excluded.isEmpty else { return base }
        let kept = keptRanges
        return base + " · 구간 \(kept.count)개 · 남은 길이 \(labelScale.timeLabel(for: kept.reduce(.zero) { $0 + $1.duration }))"
    }

    /// 손잡이 구간을 뺀 구간에 더하고(#99) 손잡이를 바깥 구간으로 되돌린다. 겹치거나 맞닿은 뺀 구간은 하나로 합친다.
    private func excludeSelection() {
        guard canExclude else { return }
        player?.pause()
        excluded = RangeExclusion.normalized(excluded + [range], within: outer)
        selectedExcluded = nil
        range = outer
    }

    /// 뺀 구간을 다시 포함한다(#99). `target`이 없으면 고른 뺀 구간이다.
    private func restore(_ target: CMTimeRange? = nil) {
        guard let restoring = target ?? selectedExcluded else { return }
        excluded.removeAll { $0 == restoring }
        selectedExcluded = nil
    }

    /// 대상의 값으로 창을 다시 맞춘다(열 때·적용 뒤·바깥에서 바뀔 때).
    private func reset(to values: ClipEditValues) {
        range = values.range
        outer = values.range
        excluded = values.excluded
        selectedExcluded = nil
        crop = values.crop
    }

    /// 크롭은 영상에만 반영한다.
    private var cropToApply: ClipCrop? {
        asset?.kind == .video ? crop : nil
    }

    /// 창 제목 "클립 편집 — 이름 (프로젝트 이름)".
    private var windowTitle: String {
        asset == nil ? "클립 편집" : "클립 편집 — \(targetName) (\(editor.project.name))"
    }

    /// 대상 이름. 클립은 별칭이 있으면 별칭이다.
    private var targetName: String {
        guard let asset else { return "" }
        if case let .clip(clipID) = kind, let clip = editor.currentSequence.clip(id: clipID) {
            return clip.displayName(assetName: asset.name)
        }
        return asset.name
    }

    /// 대상의 지금 구간과 크롭. 원본은 사용 구간(없으면 전체), 클립은 쓰는 원본 구간이다. 대상이 없으면 `nil`.
    private static func currentValues(of kind: ClipEditTarget, in editor: ProjectEditor) -> ClipEditValues? {
        switch kind {
        case let .asset(assetID):
            return editor.asset(id: assetID).map {
                ClipEditValues(range: $0.usedRange ?? CMTimeRange(start: .zero, duration: $0.duration), excluded: $0.excludedRanges, crop: $0.crop)
            }
        case let .clip(clipID):
            return editor.currentSequence.clip(id: clipID).map { ClipEditValues(range: $0.sourceRange, crop: $0.crop) }
        }
    }

    private func zoomBar(by factor: Double) {
        guard let asset else { return }
        setBarZoom(barZoom.zoomed(by: factor, duration: asset.duration, visibleWidth: barViewport.visibleWidth))
    }

    /// 막대 배율을 바꾼다. 재생 위치가 보이고 있으면 그 자리에, 아니면 가운데에 오도록 스크롤한다.
    private func setBarZoom(_ newZoom: TrimBarZoom) {
        guard let asset, barViewport.visibleWidth > 0 else { return }
        let duration = asset.duration
        let width = barViewport.visibleWidth
        let zoom = newZoom.zoomed(by: 1, duration: duration, visibleWidth: width)
        guard zoom != barZoom else { return }
        let anchor = player?.currentTime ?? range.start
        let anchorX = barZoom.x(for: anchor, duration: duration, visibleWidth: width) - barViewport.offset
        let viewX = (0 ... width).contains(anchorX) ? anchorX : width / 2
        barZoom = zoom
        let offset = zoom.scrollOffset(keeping: anchor, atViewX: viewX, duration: duration, visibleWidth: width)
        barViewport.offset = offset
        // 막대 폭이 새 배율로 바뀐 뒤에 스크롤해야 새 폭 안에서 맞춰진다.
        Task { @MainActor in barScrollPosition.scrollTo(x: offset) }
    }

    /// 보기 메뉴 확대·축소·전체 맞춤(⌘=/⌘-/⌘0). 대상이 없으면 `nil`이라 타임라인 메뉴도 보이지 않는다.
    private var barZoomCommand: ZoomCommand? {
        guard let asset else { return nil }
        return ZoomCommand(
            target: "필름스트립",
            zoomIn: barZoom.canZoomIn(duration: asset.duration, visibleWidth: barViewport.visibleWidth) ? { zoomBar(by: TrimBarZoom.stepFactor) } : nil,
            zoomOut: barZoom.canZoomOut ? { zoomBar(by: 1 / TrimBarZoom.stepFactor) } : nil,
            fit: barZoom.isFit ? nil : { setBarZoom(TrimBarZoom()) }
        )
    }

    private func moveEdge(_ edge: ClipEdge, to time: CMTime) {
        guard let asset else { return }
        activeEdge = edge
        range = TrimRange.moving(range, edge: edge, to: time, sourceDuration: asset.duration)
        player?.seek(to: edge == .start ? range.start : range.end)
    }

    /// Space는 두 탭 모두 재생/일시정지, ↑/↓는 트림 탭에서만 구간을 옮긴다. 이 창이 앞에 있을 때만 받는다.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let asset else { return .ignored }
        switch press.key {
        case .space:
            togglePlayback()
        case .delete, .deleteForward:
            // 이 창이 앞에 있을 때만 받아 타임라인·미디어 패널 삭제로 가지 않는다(#99).
            guard session.tab == .trim || asset.kind != .video else { return .ignored }
            excludeSelection()
        default:
            guard session.tab == .trim || asset.kind != .video else { return .ignored }
            player?.beginScrubbing()
            let step = press.modifiers.contains(.shift) ? TrimRange.largeStep : TrimRange.smallStep
            let delta = press.key == .upArrow ? step : CMTime.zero - step
            range = TrimRange.nudging(range, edge: activeEdge, by: delta, sourceDuration: asset.duration)
            player?.seek(to: activeEdge == .start ? range.start : range.end)
        }
        return .handled
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play(keptRanges)
        }
    }

    private func saveAsNewItem(_ asset: MediaAsset) {
        editor.addTrimmedAsset(from: asset.id, start: range.start, end: range.end, excluded: excluded, crop: cropToApply ?? ClipCrop())
        close()
    }

    /// 파일 > ⌘S: 기본 버튼처럼 적용하되 창은 열어 둔다(#92). 원본 항목은 새 파생 항목을 만들고 창이 그 항목을 보여준다
    /// — 원본에 머물면 ⌘S를 누를 때마다 같은 항목이 또 생기기 때문이다(자르기 뒤와 같은 방식).
    private func saveKeepingWindow() {
        guard let asset else { return }
        if case .asset = kind, !asset.isDerived {
            guard let newID = editor.addTrimmedAsset(from: asset.id, start: range.start, end: range.end, excluded: excluded, crop: cropToApply ?? ClipCrop()) else { return }
            kind = .asset(newID)
            session.target = kind
            if let current = Self.currentValues(of: kind, in: editor) {
                committed = current
                reset(to: current)
            }
        } else {
            applyDefault()
        }
    }

    /// 기본 버튼이 하는 일: 클립·파생 항목은 고친 구간·크롭을 적용하고, 원본 항목은 새 파생 항목으로 저장한다(원본은 바꾸지 않는다).
    /// 닫기 확인의 "적용"도 이것을 쓴다.
    private func applyDefault() {
        guard let asset else { return }
        switch kind {
        case let .clip(clipID):
            editor.commitClipTrim(clipID, start: range.start, end: range.end, excluded: excluded, crop: cropToApply)
        case .asset where asset.isDerived:
            editor.setUsedRange(start: range.start, end: range.end, excluded: excluded, crop: cropToApply, for: asset.id)
        case .asset:
            editor.addTrimmedAsset(from: asset.id, start: range.start, end: range.end, excluded: excluded, crop: cropToApply ?? ClipCrop())
        }
    }

    /// 확정했거나 버리기로 한 뒤 묻지 않고 창을 닫는다.
    private func close() {
        session.hasUnappliedChanges = false
        dismiss()
    }

    /// 적용하지 않은 채 닫을 때의 확인 문구. 원본 항목은 바꿀 수 없어 "새 항목으로 저장"을 묻는다.
    private var closePrompt: UnsavedChangesPrompt {
        let isOriginalAsset = if case .asset = kind {
            asset?.isDerived == false
        } else {
            false
        }
        return UnsavedChangesPrompt(
            message: "\"\(targetName)\"에서 고친 트림·크롭을 \(isOriginalAsset ? "새 항목으로 저장" : "적용")하시겠습니까?",
            information: "\(isOriginalAsset ? "저장" : "적용")하지 않으면 이 창에서 고친 내용이 사라집니다.",
            saveTitle: isOriginalAsset ? "새 항목으로 저장" : "적용",
            discardTitle: isOriginalAsset ? "저장 안 함" : "적용 안 함"
        )
    }

    /// 옮겨 둔 구간·크롭을 함께 반영해 재생 위치에서 자르고, 앞 조각을 계속 편집한다.
    /// 재생 위치는 앞 조각 가운데로 옮겨 바로 다시 자를 수 있게 한다(앞 조각의 끝에 붙어 있으면 자르기가 꺼진다).
    private func split(at time: CMTime) {
        player?.pause()
        switch kind {
        case let .clip(clipID):
            guard editor.splitClip(clipID, start: range.start, end: range.end, crop: cropToApply, at: time) else { return }
        case let .asset(assetID):
            guard let pieces = editor.splitAsset(assetID, start: range.start, end: range.end, crop: cropToApply ?? ClipCrop(), at: time) else { return }
            kind = .asset(pieces.front)
            session.target = kind
        }
        if let current = Self.currentValues(of: kind, in: editor) {
            committed = current
            reset(to: current)
            player?.seek(to: current.range.start + CMTimeMultiplyByRatio(current.range.duration, multiplier: 1, divisor: 2))
        }
    }
}

// MARK: - Crop

private extension CropAspect {
    var title: String {
        switch self {
        case .free: "자유"
        case .original: "원본"
        case .landscape16x9: "16:9"
        case .portrait9x16: "9:16"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        }
    }
}

/// 큰 영상 위에 크롭 테두리를 그린다(#85). 잘려 나갈 바깥은 어둡게, 네 모서리·네 변 손잡이를 끌어 자르고, 테두리 안을 끌어 옮긴다.
/// 끄는 동안 3분할 격자와 가운데 선을 보여준다. 끌기는 시작할 때의 크롭과 움직인 거리로 계산해 떨리지 않는다.
private struct CropOverlayView: View {
    @Binding var crop: ClipCrop
    /// 원본 화면 크기(회전 반영).
    let contentSize: CGSize
    let aspect: CropAspect
    /// 끌기를 시작할 때의 크롭. 끄는 중이 아니면 `nil`.
    @State private var dragStart: ClipCrop?
    private static let space = "cropOverlay"
    private static let handleLength = 18.0
    private static let handleThickness = 5.0

    var body: some View {
        GeometryReader { geometry in
            // 플레이어는 영상을 비율을 지켜 가운데 맞춰 보여준다.
            let picture = AVMakeRect(aspectRatio: contentSize, insideRect: CGRect(origin: .zero, size: geometry.size))
            let visible = crop.visibleRect
            let shown = CGRect(
                x: picture.minX + visible.minX * picture.width,
                y: picture.minY + visible.minY * picture.height,
                width: visible.width * picture.width,
                height: visible.height * picture.height
            )

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(picture)
                    path.addRect(shown)
                }
                .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
                    .pointerStyle(.grabIdle)
                    .gesture(moveGesture(picture: picture))
                if dragStart != nil {
                    guides(in: shown)
                }
                Rectangle()
                    .strokeBorder(.white, lineWidth: 1.5)
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
                    .allowsHitTesting(false)
                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleView(handle, shown: shown, picture: picture)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
    }

    /// 3분할 격자와 가운데 선.
    private func guides(in rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for fraction in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
                }
            }
            .stroke(.white.opacity(0.6), lineWidth: 1)
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
            .stroke(.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .allowsHitTesting(false)
    }

    private func handleView(_ handle: CropHandle, shown: CGRect, picture: CGRect) -> some View {
        let center = Self.point(of: handle, in: shown)
        let isCorner = ![.top, .bottom, .left, .right].contains(handle)
        let isHorizontalEdge = handle == .top || handle == .bottom
        let size = isCorner
            ? CGSize(width: Self.handleLength / 1.5, height: Self.handleLength / 1.5)
            : isHorizontalEdge ? CGSize(width: Self.handleLength, height: Self.handleThickness) : CGSize(width: Self.handleThickness, height: Self.handleLength)
        return Rectangle()
            .fill(.white)
            .frame(width: size.width, height: size.height)
            .shadow(radius: 1)
            // 잡기 쉽게 보이는 손잡이보다 넓게 받는다.
            .frame(width: max(size.width, 22), height: max(size.height, 22))
            .contentShape(Rectangle())
            .offset(x: center.x - max(size.width, 22) / 2, y: center.y - max(size.height, 22) / 2)
            .pointerStyle(.frameResize(position: handle.resizePosition))
            .highPriorityGesture(resizeGesture(handle, picture: picture))
    }

    private func resizeGesture(_ handle: CropHandle, picture: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                // 손잡이가 있던 자리에 움직인 거리를 더한다(잡은 자리가 손잡이 가운데가 아니어도 튀지 않는다).
                let origin = Self.point(of: handle, in: start.visibleRect)
                let point = CGPoint(x: origin.x + value.translation.width / picture.width, y: origin.y + value.translation.height / picture.height)
                let keepsCurrentRatio = NSEvent.modifierFlags.contains(.shift)
                let ratio = aspect.ratio(contentSize: contentSize) ?? (keepsCurrentRatio ? start.aspectRatio(contentSize: contentSize) : nil)
                crop = start.dragging(handle, to: point, aspectRatio: ratio, contentSize: contentSize)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func moveGesture(picture: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let start = dragStart ?? crop
                dragStart = start
                crop = start.moved(dx: value.translation.width / picture.width, dy: value.translation.height / picture.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// 사각형에서 손잡이가 있는 자리.
    private static func point(of handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

private extension CropHandle {
    var resizePosition: FrameResizePosition {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

// MARK: - Bar

/// 필름스트립 막대가 보이는 폭과 스크롤 위치(#97). 막대가 알려 주고, 창이 확대할 때 기준점을 잡는 데 쓴다.
private struct TrimBarViewport: Equatable {
    var visibleWidth = 0.0
    var offset = 0.0
}

/// 원본 전체 필름스트립(오디오는 파형) 위에 고른 구간을 노란 테두리로, 바깥은 어둡게 보여준다.
/// 양 끝 손잡이를 끌어 구간을 바꾸고(트림 탭), 띠를 누르거나 끌어 재생 위치를 옮긴다.
/// 확대하면 가로로 스크롤되고, 손잡이를 가장자리까지 끌면 그쪽으로 스크롤한다(#97). ⌥를 누르고 끌면 5분의 1만 옮긴다.
/// 끌기 시작하면 재생을 멈춘다(#95).
private struct TrimBarView: View {
    let asset: MediaAsset
    let range: CMTimeRange
    /// 뺀 구간들(#99). 빗금으로 그리고, 누르면 골라 되살릴 수 있다.
    let excluded: [CMTimeRange]
    let selectedExcluded: CMTimeRange?
    let playhead: CMTime
    let activeEdge: ClipEdge
    /// 크롭 탭에서는 구간 손잡이를 감추고 재생 위치만 옮긴다(#89).
    let allowsRangeEditing: Bool
    let canExclude: Bool
    let selectExcluded: (CMTimeRange?) -> Void
    let excludeSelection: () -> Void
    let restore: (CMTimeRange) -> Void
    let zoom: TrimBarZoom
    @Binding var scrollPosition: ScrollPosition
    @Binding var viewport: TrimBarViewport
    /// 핀치로 바꾼 배율. 창이 기준점을 지키며 반영한다.
    let setZoom: (TrimBarZoom) -> Void
    let beginScrubbing: () -> Void
    let moveEdge: (ClipEdge, CMTime) -> Void
    let scrub: (CMTime) -> Void
    @State private var lastDrag: (x: Double, time: CMTime)?
    @State private var autoScroll: AutoScroll?
    @State private var pinchStart: TrimBarZoom?
    /// 끄는 중인 포인터 자리(막대 안 좌표)와 그 시각. 말풍선을 띄우는 데 쓴다(#102).
    @State private var dragHint: (x: Double, time: CMTime)?
    @State private var isOptionHeld = false
    /// 말풍선 시각 글자(소수 둘째 자리까지).
    private static let hintScale = TimelineScale(pointsPerSecond: 100)
    static let height = TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
    private static let handleWidth = 12.0
    private static let space = "trimBar"
    /// 필름스트립을 이 폭 단위로 나눠, 보이는 부분 근처만 그린다(크게 확대해도 썸네일을 다 만들지 않게).
    private static let segmentWidth = 512.0
    /// 손잡이를 이 거리 안까지 끌면 그쪽으로 스크롤한다.
    private static let autoScrollZone = 24.0
    private static let autoScrollStep = 12.0

    /// 손잡이를 막대 가장자리까지 끌어 스크롤하는 중. 포인터는 보이는 폭 안 `viewX`에 머문다.
    private struct AutoScroll: Equatable {
        let edge: ClipEdge
        let direction: Double
        var viewX: Double
    }

    var body: some View {
        GeometryReader { geometry in
            let visibleWidth = geometry.size.width
            ScrollView(.horizontal) {
                bar(visibleWidth: visibleWidth)
            }
            .scrollIndicators(zoom.isFit ? .hidden : .automatic)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x } action: { _, offset in
                viewport.offset = offset
            }
            .onChange(of: visibleWidth, initial: true) {
                viewport.visibleWidth = visibleWidth
            }
        }
        .frame(height: Self.height)
        // 끄는 동안 포인터 위에 시각과 ⌥ 정밀 안내를 띄운다. 기본 툴팁은 끄는 동안 뜨지 않아 직접 그린다(#102).
        .overlay(alignment: .topLeading) {
            if let dragHint {
                dragHintBubble(dragHint)
            }
        }
        .onModifierKeysChanged(mask: .option, initial: true) { _, keys in
            isOptionHeld = keys.contains(.option)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    setZoom(start.zoomed(by: value.magnification, duration: asset.duration, visibleWidth: viewport.visibleWidth))
                }
                .onEnded { _ in pinchStart = nil }
        )
        .task(id: autoScroll.map { "\($0.edge)\($0.direction)" }) {
            await runAutoScroll()
        }
    }

    private func bar(visibleWidth: Double) -> some View {
        let duration = asset.duration
        let contentWidth = zoom.contentWidth(visibleWidth: visibleWidth)
        let x = { (time: CMTime) in zoom.x(for: time, duration: duration, visibleWidth: visibleWidth) }
        let startX = x(range.start)
        let endX = x(range.end)

        return ZStack(alignment: .topLeading) {
            filmstrip(contentWidth: contentWidth, visibleWidth: visibleWidth)
                .gesture(scrubGesture(visibleWidth: visibleWidth))
                .contextMenu {
                    if allowsRangeEditing {
                        Button("구간 빼기", action: excludeSelection)
                            .disabled(!canExclude)
                    }
                }
            // 뺀 구간(#99)은 빗금으로. 누르면 고르고, 우클릭으로 되살린다.
            ForEach(excluded, id: \.self) { excludedRange in
                let minX = x(excludedRange.start)
                let isSelected = excludedRange == selectedExcluded
                HatchedRangeView(isSelected: isSelected)
                    .frame(width: max(x(excludedRange.end) - minX, 2), height: Self.height)
                    .contentShape(Rectangle())
                    .offset(x: minX)
                    .onTapGesture { selectExcluded(isSelected ? nil : excludedRange) }
                    .contextMenu {
                        Button("되살리기") { restore(excludedRange) }
                    }
                    .help("뺀 구간 — 눌러 고르고 \"되살리기\"로 다시 포함합니다")
                    .allowsHitTesting(allowsRangeEditing)
            }
            // 고르지 않은 바깥은 어둡게.
            Color.black.opacity(0.55)
                .frame(width: max(startX, 0))
                .allowsHitTesting(false)
            Color.black.opacity(0.55)
                .frame(width: max(contentWidth - endX, 0))
                .offset(x: endX)
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.yellow, lineWidth: 3)
                .frame(width: max(endX - startX, 6))
                .offset(x: startX)
                .allowsHitTesting(false)
            if allowsRangeEditing {
                handle(.start, x: startX, visibleWidth: visibleWidth)
                handle(.end, x: endX - Self.handleWidth, visibleWidth: visibleWidth)
            }
            Rectangle()
                .fill(.white)
                .frame(width: 2)
                .shadow(radius: 1)
                .offset(x: x(playhead) - 1)
                .allowsHitTesting(false)
        }
        .frame(width: contentWidth, height: Self.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }

    /// 보이는 부분과 그 양옆 한 화면만 조각으로 그린다. 조각마다 그 구간의 필름스트립(오디오는 파형)을 만든다.
    private func filmstrip(contentWidth: Double, visibleWidth: Double) -> some View {
        let duration = asset.duration
        let segmentCount = max(Int((contentWidth / Self.segmentWidth).rounded(.up)), 1)
        let first = max(Int((viewport.offset - visibleWidth) / Self.segmentWidth), 0)
        let last = min(Int((viewport.offset + visibleWidth * 2) / Self.segmentWidth), segmentCount - 1)
        return ZStack(alignment: .topLeading) {
            ForEach(first ... max(first, last), id: \.self) { index in
                let minX = Double(index) * Self.segmentWidth
                let width = min(Self.segmentWidth, contentWidth - minX)
                let start = zoom.time(forX: minX, duration: duration, visibleWidth: visibleWidth)
                let end = zoom.time(forX: minX + width, duration: duration, visibleWidth: visibleWidth)
                // 같은 조각이면 같은 ID라 다시 그릴 때 썸네일을 다시 만들지 않는다.
                if width > 0, let clip = Clip(id: asset.id, assetID: asset.id, sourceRange: CMTimeRange(start: start, end: end), timelineStart: .zero) {
                    ClipContentView(asset: asset, clip: clip, width: width, showsFilmstrip: true, showsWaveform: asset.kind == .audio)
                        .frame(width: width, height: Self.height)
                        .offset(x: minX)
                }
            }
        }
        .frame(width: contentWidth, height: Self.height, alignment: .topLeading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private func scrubGesture(visibleWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let time = draggedTime(to: value.location.x, from: playhead, visibleWidth: visibleWidth)
                scrub(time)
            }
            .onEnded { _ in
                lastDrag = nil
                dragHint = nil
            }
    }

    private func handle(_ edge: ClipEdge, x: Double, visibleWidth: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.yellow)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.5))
                    .frame(width: 2, height: Self.height / 2)
            }
            .overlay {
                // 방향키가 옮기는 쪽을 테두리로 알린다.
                if edge == activeEdge {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.5)
                }
            }
            .frame(width: Self.handleWidth, height: Self.height)
            .offset(x: x)
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        let current = edge == .start ? range.start : range.end
                        moveEdge(edge, draggedTime(to: value.location.x, from: current, visibleWidth: visibleWidth))
                        updateAutoScroll(edge: edge, viewX: value.location.x - viewport.offset)
                    }
                    .onEnded { _ in
                        lastDrag = nil
                        dragHint = nil
                        autoScroll = nil
                    }
            )
            .help(edge == .start ? "시작 손잡이 — 끌어서 시작을 바꿉니다(⌥를 누르면 정밀하게)" : "끝 손잡이 — 끌어서 끝을 바꿉니다(⌥를 누르면 정밀하게)")
    }

    /// 끌기 첫 이벤트에 재생을 멈추고, ⌥를 누르고 있으면 직전 위치에서 움직인 거리의 5분의 1만 옮긴다.
    private func draggedTime(to x: Double, from currentTime: CMTime, visibleWidth: Double) -> CMTime {
        if lastDrag == nil {
            beginScrubbing()
        }
        let previous = lastDrag ?? (x, currentTime)
        let time = zoom.draggedTime(
            to: x,
            from: previous.x,
            previousTime: previous.time,
            isPrecise: NSEvent.modifierFlags.contains(.option),
            duration: asset.duration,
            visibleWidth: visibleWidth
        )
        lastDrag = (x, time)
        dragHint = (x, time)
        return time
    }

    /// "0:12.40 · ⌥ 누르면 정밀하게" / ⌥를 누르면 "0:12.40 · 정밀 1/5". 막대 밖으로 나가지 않게 좌우를 맞춘다.
    private func dragHintBubble(_ hint: (x: Double, time: CMTime)) -> some View {
        let text = "\(Self.hintScale.timeLabel(for: hint.time)) · \(isOptionHeld ? "정밀 1/5" : "⌥ 누르면 정밀하게")"
        let width = 190.0
        let viewX = hint.x - viewport.offset
        let left = min(max(viewX - width / 2, 0), max(viewport.visibleWidth - width, 0))
        return Text(text)
            .font(.caption.weight(isOptionHeld ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isOptionHeld ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOptionHeld ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Capsule())
            .frame(width: width)
            .offset(x: left, y: -30)
            .allowsHitTesting(false)
    }

    private func updateAutoScroll(edge: ClipEdge, viewX: Double) {
        let width = viewport.visibleWidth
        let direction: Double? = zoom.isFit ? nil : viewX < Self.autoScrollZone ? -1 : viewX > width - Self.autoScrollZone ? 1 : nil
        if let direction {
            let clampedX = min(max(viewX, 0), width)
            if autoScroll?.edge == edge, autoScroll?.direction == direction {
                autoScroll?.viewX = clampedX
            } else {
                autoScroll = AutoScroll(edge: edge, direction: direction, viewX: clampedX)
            }
        } else if autoScroll != nil {
            autoScroll = nil
        }
    }

    /// 손잡이를 가장자리에 대고 있는 동안 조금씩 스크롤하며 손잡이를 포인터 아래 시각으로 옮긴다.
    private func runAutoScroll() async {
        while let current = autoScroll, !Task.isCancelled {
            let width = viewport.visibleWidth
            let maximumOffset = max(zoom.contentWidth(visibleWidth: width) - width, 0)
            let offset = min(max(viewport.offset + current.direction * Self.autoScrollStep, 0), maximumOffset)
            guard offset != viewport.offset else { return }
            viewport.offset = offset
            scrollPosition.scrollTo(x: offset)
            let x = offset + current.viewX
            let time = zoom.time(forX: x, duration: asset.duration, visibleWidth: width)
            moveEdge(current.edge, time)
            lastDrag = (x, time)
            dragHint = (x, time)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

/// 뺀 구간(#99) 표시. 어둡게 덮고 빗금을 긋는다. 고르면 테두리를 두른다.
private struct HatchedRangeView: View {
    let isSelected: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.6)))
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 8
            }
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.stroke(stripes, with: .color(.red.opacity(0.7)), lineWidth: 1.5)
        }
        .overlay {
            if isSelected {
                Rectangle().strokeBorder(.white, lineWidth: 2)
            }
        }
    }
}

// MARK: - Player

/// 클립 편집 창에서 원본을 재생하는 플레이어. 시퀀스 미리보기(`PreviewPlayer`)와 따로 둔다.
@Observable
final class TrimPlayer {
    let player = AVPlayer()
    private(set) var currentTime: CMTime = .zero
    private(set) var isPlaying = false
    @ObservationIgnored private var timeObserver: Any?
    /// 탐색이 끝나기 전에 들어온 다음 위치(#95). 앞 탐색이 끝나면 마지막 위치 하나만 이어서 찾는다("chase seek").
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeekTime: CMTime?
    /// 뺀 구간을 건너뛰는 경계 관찰자(#99). 재생할 때 걸고 멈추면 뗀다.
    @ObservationIgnored private var skipObserver: Any?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 탐색 중에는 옛 위치가 들어와 재생 위치 표시가 되돌아가지 않게 한다.
                if !self.isSeeking {
                    self.currentTime = time
                }
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    /// `time`의 프레임을 보여준다. 끄는 동안 이벤트마다 불려도, 앞 탐색이 끝난 뒤 마지막 위치로만 이어 찾아
    /// 화면이 포인터를 늦게 따라오거나 건너뛰지 않는다(#95).
    func seek(to time: CMTime) {
        currentTime = time
        guard !isSeeking else {
            pendingSeekTime = time
            return
        }
        isSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.seekFinished() }
        }
    }

    private func seekFinished() {
        isSeeking = false
        if let next = pendingSeekTime {
            pendingSeekTime = nil
            seek(to: next)
        }
    }

    /// 손잡이·재생 위치를 끌거나 ↑/↓로 옮기기 시작할 때. 재생을 멈추고 손을 떼도 멈춘 채 둔다(#95).
    func beginScrubbing() {
        if isPlaying || player.rate != 0 {
            pause()
        }
    }

    /// 남은 구간들만 이어 재생하고 마지막 구간 끝에서 멈춘다(#99, 뺀 구간은 건너뛴다). 재생 위치가 처음 구간 앞이거나 끝이면 처음부터,
    /// 뺀 구간 안이면 다음 구간부터.
    func play(_ segments: [CMTimeRange]) {
        guard let first = segments.first, let last = segments.last else { return }
        removeSkipObserver()
        player.currentItem?.forwardPlaybackEndTime = last.end
        if currentTime < first.start || currentTime >= last.end - Clip.minimumDuration {
            seek(to: first.start)
        } else if let next = segments.first(where: { currentTime < $0.start }), !segments.contains(where: { $0.containsTime(currentTime) }) {
            seek(to: next.start)
        }
        let jumps = zip(segments, segments.dropFirst()).map { (from: $0.end, to: $1.start) }
        if !jumps.isEmpty {
            skipObserver = player.addBoundaryTimeObserver(forTimes: jumps.map { NSValue(time: $0.from) }, queue: .main) { [weak self] in
                MainActor.assumeIsolated { self?.skipGap(jumps) }
            }
        }
        player.play()
        isPlaying = true
    }

    /// 경계에 닿으면 가장 가까운 뺀 구간의 끝으로 건너뛴다.
    private func skipGap(_ jumps: [(from: CMTime, to: CMTime)]) {
        let now = player.currentTime()
        guard let jump = jumps.min(by: { abs(($0.from - now).seconds) < abs(($1.from - now).seconds) }) else { return }
        player.seek(to: jump.to, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func removeSkipObserver() {
        if let skipObserver {
            player.removeTimeObserver(skipObserver)
            self.skipObserver = nil
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        removeSkipObserver()
    }

    func stop() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
