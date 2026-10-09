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
    /// 창에 적용하지 않은 변경이 있는지. 창이 알려 준다.
    var hasUnappliedChanges = false
    /// 창이 열려 있는지. 창이 알려 준다.
    var isWindowOpen = false

    init(editor: ProjectEditor) {
        self.editor = editor
    }

    /// `newTarget`을 연다. 창에 같은 대상이 열려 있으면 그대로 두고, 다른 대상을 고치던 중이면 창이 먼저 묻는다.
    func open(_ newTarget: ClipEditTarget) {
        guard isWindowOpen else { return show(newTarget) }
        if newTarget == target {
            pendingTarget = nil
        } else if hasUnappliedChanges {
            pendingTarget = newTarget
        } else {
            show(newTarget)
        }
    }

    /// 고치던 값을 버리고 `newTarget`을 연다.
    func show(_ newTarget: ClipEditTarget) {
        target = newTarget
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
        Group {
            if let session, let target = session.target {
                ClipEditView(session: session, target: target)
                    .id(session.openID)
            } else {
                ContentUnavailableView("대상이 없습니다", systemImage: "film", description: Text("프로젝트 창에서 클립을 두 번 누르거나 ⌘T로 여세요"))
                    .frame(minWidth: 480, minHeight: 320)
                    .navigationTitle("클립 편집")
            }
        }
        .onAppear { session?.isWindowOpen = true }
        .onDisappear { session?.isWindowOpen = false }
    }
}

/// 클립 편집 창의 탭.
private enum ClipEditTab {
    /// 시간 자르기(#81).
    case trim
    /// 화면 자르기(#85).
    case crop
}

/// 대상이 가진(또는 창에서 고치는) 구간과 크롭.
private struct ClipEditValues: Equatable {
    var range: CMTimeRange
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
    @State private var crop: ClipCrop
    /// 대상이 마지막으로 가진 값. 고치는 값과 다르면 적용하지 않은 변경이 있다.
    @State private var committed: ClipEditValues?
    @State private var tab = ClipEditTab.trim
    @State private var cropAspect = CropAspect.free
    /// 원본 화면 크기(회전 반영). 크롭 테두리와 비율 계산에 쓴다.
    @State private var contentSize: CGSize?
    /// 방향키가 옮기는 손잡이. 마지막으로 잡은 쪽이다.
    @State private var activeEdge = ClipEdge.end
    @State private var player: TrimPlayer?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    /// 시간 글자(분:초.소수 첫째 자리)를 만드는 데만 쓴다.
    private let labelScale = TimelineScale(pointsPerSecond: 40)

    init(session: ClipEditSession, target: ClipEditTarget) {
        self.session = session
        let values = Self.currentValues(of: target, in: session.editor)
        _kind = State(initialValue: target)
        _range = State(initialValue: values?.range ?? CMTimeRange(start: .zero, duration: .zero))
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
                    Picker("", selection: $tab) {
                        Text("트림").tag(ClipEditTab.trim)
                        Text("크롭").tag(ClipEditTab.crop)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                }
                picture(for: asset)
                if tab == .crop, asset.kind == .video {
                    cropControls
                } else {
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
                            playhead: player?.currentTime ?? range.start,
                            activeEdge: activeEdge,
                            moveEdge: moveEdge,
                            scrub: { player?.seek(to: $0) }
                        )
                    }
                    timeSummary
                }
                actions(for: asset)
            } else {
                ContentUnavailableView("대상이 없습니다", systemImage: "scissors", description: Text("원본이나 클립이 지워졌습니다"))
                Button("닫기") { dismiss() }
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 540)
        .navigationTitle(windowTitle)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .space]) { press in
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
                range = values.range
                crop = values.crop
            }
        }
        .onChange(of: hasUnappliedChanges, initial: true) { _, hasChanges in
            session.hasUnappliedChanges = hasChanges
        }
        .alert("적용하지 않은 변경이 있습니다", isPresented: isAskingToSwitch) {
            Button("변경 버리기", role: .destructive) {
                if let pendingTarget = session.pendingTarget {
                    session.show(pendingTarget)
                }
            }
            Button("취소", role: .cancel) { session.pendingTarget = nil }
        } message: {
            Text("다른 대상을 열면 이 창에서 고친 트림·크롭이 사라집니다.")
        }
    }

    // MARK: - Parts

    private func picture(for asset: MediaAsset) -> some View {
        Group {
            if asset.kind == .video, let player {
                PlayerSurfaceView(player: player.player)
                    .overlay {
                        if tab == .crop, let contentSize {
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

    private var timeSummary: some View {
        HStack {
            Text("시작 \(labelScale.timeLabel(for: range.start)) · 끝 \(labelScale.timeLabel(for: range.end)) · 길이 \(labelScale.timeLabel(for: range.duration))")
                .monospacedDigit()
            Spacer()
            Text("↑/↓ \(activeEdge == .start ? "시작" : "끝")을 0.1초씩, ⇧와 함께 1초씩")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
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
            if tab == .trim || asset.kind != .video {
                Button("자르기") { split(at: playhead) }
                    .disabled(!TrimRange.canSplit(range, at: playhead))
                    .help("재생 위치에서 둘로 자릅니다. 옮겨 둔 손잡이 구간과 크롭도 함께 반영합니다")
            }
            Spacer()
            Button("취소", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            switch kind {
            case .asset:
                // 원본 항목은 바꾸지 않는다. 파생 항목만 자기 구간·크롭을 "적용"으로 바꿀 수 있다.
                if asset.isDerived {
                    Button("새 항목으로 저장") { saveAsNewItem(asset) }
                        .help("이 구간·크롭으로 파생 항목을 하나 더 미디어 패널에 추가합니다(파일은 복사하지 않음)")
                    Button("적용") {
                        editor.setUsedRange(start: range.start, end: range.end, crop: cropToApply, for: asset.id)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("이 파생 항목이 쓰는 구간·크롭을 바꿉니다")
                } else {
                    Button("새 항목으로 저장") { saveAsNewItem(asset) }
                        .keyboardShortcut(.defaultAction)
                        .help("이 구간·크롭으로 파생 항목을 미디어 패널에 추가합니다. 원본 항목·파일은 그대로입니다")
                }
            case let .clip(clipID):
                Button("적용") {
                    editor.commitClipTrim(clipID, start: range.start, end: range.end, crop: cropToApply)
                    dismiss()
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
        committed.map { $0 != ClipEditValues(range: range, crop: crop) } ?? false
    }

    /// 크롭은 영상에만 반영한다.
    private var cropToApply: ClipCrop? {
        asset?.kind == .video ? crop : nil
    }

    /// 창 제목 "클립 편집 — 이름 (프로젝트 이름)".
    private var windowTitle: String {
        guard let asset else { return "클립 편집" }
        let name: String = if case let .clip(clipID) = kind, let clip = editor.currentSequence.clip(id: clipID) {
            clip.displayName(assetName: asset.name)
        } else {
            asset.name
        }
        return "클립 편집 — \(name) (\(editor.project.name))"
    }

    /// 대상의 지금 구간과 크롭. 원본은 사용 구간(없으면 전체), 클립은 쓰는 원본 구간이다. 대상이 없으면 `nil`.
    private static func currentValues(of kind: ClipEditTarget, in editor: ProjectEditor) -> ClipEditValues? {
        switch kind {
        case let .asset(assetID):
            return editor.asset(id: assetID).map { ClipEditValues(range: $0.usedRange ?? CMTimeRange(start: .zero, duration: $0.duration), crop: $0.crop) }
        case let .clip(clipID):
            return editor.currentSequence.clip(id: clipID).map { ClipEditValues(range: $0.sourceRange, crop: $0.crop) }
        }
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
        default:
            guard tab == .trim || asset.kind != .video else { return .ignored }
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
            player.play(range)
        }
    }

    private func saveAsNewItem(_ asset: MediaAsset) {
        editor.addTrimmedAsset(from: asset.id, start: range.start, end: range.end, crop: cropToApply ?? ClipCrop())
        dismiss()
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
            range = current.range
            crop = current.crop
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

/// 원본 전체 필름스트립(오디오는 파형) 위에 고른 구간을 노란 테두리로, 바깥은 어둡게 보여준다.
/// 양 끝 손잡이를 끌어 구간을 바꾸고, 띠를 누르거나 끌어 재생 위치를 옮긴다.
private struct TrimBarView: View {
    let asset: MediaAsset
    let range: CMTimeRange
    let playhead: CMTime
    let activeEdge: ClipEdge
    let moveEdge: (ClipEdge, CMTime) -> Void
    let scrub: (CMTime) -> Void
    private static let height = TimelineMetrics.trackHeight - TimelineMetrics.clipVerticalInset * 2
    private static let handleWidth = 12.0
    private static let space = "trimBar"

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (time: CMTime) in asset.duration.seconds > 0 ? time.seconds / asset.duration.seconds * width : 0 }
            let time = { (x: Double) in CMTime(seconds: min(max(x, 0), width) / max(width, 1) * asset.duration.seconds, preferredTimescale: standardTimescale) }
            let startX = x(range.start)
            let endX = x(range.end)

            ZStack(alignment: .topLeading) {
                content(width: width)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { scrub(time($0.location.x)) })
                // 고르지 않은 바깥은 어둡게.
                Color.black.opacity(0.55)
                    .frame(width: max(startX, 0))
                    .allowsHitTesting(false)
                Color.black.opacity(0.55)
                    .frame(width: max(width - endX, 0))
                    .offset(x: endX)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.yellow, lineWidth: 3)
                    .frame(width: max(endX - startX, 6))
                    .offset(x: startX)
                    .allowsHitTesting(false)
                handle(.start, x: startX, time: time)
                handle(.end, x: endX - Self.handleWidth, time: time)
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 1)
                    .offset(x: x(playhead) - 1)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: Self.height)
    }

    private func content(width: Double) -> some View {
        let fullClip = Clip(assetID: asset.id, sourceRange: CMTimeRange(start: .zero, duration: asset.duration), timelineStart: .zero)
        return Group {
            if let fullClip {
                ClipContentView(asset: asset, clip: fullClip, width: width, showsFilmstrip: true, showsWaveform: asset.kind == .audio)
            }
        }
        .frame(width: width, height: Self.height)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private func handle(_ edge: ClipEdge, x: Double, time: @escaping (Double) -> CMTime) -> some View {
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
                    .onChanged { moveEdge(edge, time($0.location.x)) }
            )
            .help(edge == .start ? "시작 손잡이 — 끌어서 시작을 바꿉니다" : "끝 손잡이 — 끌어서 끝을 바꿉니다")
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

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time
                self?.isPlaying = self?.player.rate != 0
            }
        }
    }

    func seek(to time: CMTime) {
        currentTime = time
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 고른 구간만 재생하고 끝에서 멈춘다. 재생 위치가 구간 밖이거나 끝이면 처음부터.
    func play(_ range: CMTimeRange) {
        player.currentItem?.forwardPlaybackEndTime = range.end
        if currentTime < range.start || currentTime >= range.end - Clip.minimumDuration {
            seek(to: range.start)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
