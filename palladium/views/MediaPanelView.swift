import AppKit
import CoreMedia
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 프리미어 프로의 프로젝트 패널처럼 한 번 클릭은 선택만 하고, 더블클릭하면 원본을 미리보기(소스 모니터)에서 연다.
/// 포토샵 레이어처럼 원본 이름을 목록에서 바로 바꿔 정리한다(F2 또는 우클릭 > 이름 변경).
/// 폴더 트리(#93)로 원본을 분류한다. 폴더 안에 폴더를 두고, 폴더마다 접고 편다. 맨 위 단계에는 폴더와 어느 폴더에도 없는 원본이 함께 보인다.
/// 원본·폴더를 끌어다 다른 폴더 안이나 맨 위로 옮긴다. 원본은 한 폴더에만 속한다. 폴더·원본은 각각 이름순이고 폴더가 먼저다(#94).
struct MediaPanelView: View {
    /// 원본 정리(이름·색상 레이블·태그)는 편집기 커맨드로 한다.
    let editor: ProjectEditor
    /// 고른 원본들(#86). ⌘ 클릭·⇧ 클릭·⌘A로 여러 개를 고른다.
    @Binding var selectedAssetIDs: Set<MediaAsset.ID>
    let openAsset: (MediaAsset.ID) -> Void
    /// 행·폴더 머리는 원본 ID를 받으려고 문자열 놓기를 받는데, Finder에서 끈 파일도 문자열(파일 URL)로 들어오므로 가져오기로 넘긴다.
    var importFiles: ([URL]) -> Void = { _ in }
    /// 목록에 포커스가 있는지. 편집 창이 ⌫를 타임라인 클립 삭제로 가로채지 않게 알린다.
    var isListFocused: Binding<Bool> = .constant(false)
    /// 항목을 클립 편집 창으로 연다(#81·#85).
    var openClipEditor: (MediaAsset.ID) -> Void = { _ in }
    /// 타임라인의 "미디어 패널에서 원본 보기"(#101). 바뀌면 목록이 포커스를 받고 그 원본 줄까지 스크롤한다.
    var revealRequest: AssetRevealRequest?
    /// 빈 곳 우클릭 > 가져오기…(#104). 파일 > 가져오기(⌘I)와 같다.
    var importMedia: () -> Void = {}
    @State private var filter = MediaFilter()
    /// 고른 순서(#86). 타임라인에 이어 붙이거나 폴더로 옮길 때 이 순서를 쓴다.
    @State private var selectionOrder: [MediaAsset.ID] = []
    @FocusState private var listHasFocus: Bool
    /// 클립이 쓰고 있어 확인을 기다리는 삭제(#60).
    @State private var pendingDeletion: Set<MediaAsset.ID>?
    /// 태그를 편집 중인 원본. 편집 창이 닫히면 `nil`.
    @State private var tagEditingAssetID: MediaAsset.ID?
    @State private var tagText = ""
    /// 목록 안에서 이름을 바꾸는 중인 원본.
    @State private var renamingAssetID: MediaAsset.ID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool
    /// 이름을 바꾸는 중인 폴더.
    @State private var renamingFolderID: MediaFolder.ID?
    @State private var folderNameText = ""
    /// 접어 둔 폴더(#93). 앱을 다시 켜도 유지한다.
    @AppStorage(AppPreferences.collapsedMediaFoldersKey) private var collapsedFolderText = ""
    /// 끄는 중 포인터가 머문 접힌 폴더. 잠시 머물면 펼친다.
    @State private var dropHoverFolderID: MediaFolder.ID?
    private static let dropHoverExpandDelay = Duration.milliseconds(700)
    /// 끄는 동안 목록 끝 띠에 커서가 있으면 한 번에 굴릴 거리(pt, 위로 음수). 띠를 벗어나면 `nil`(#108).
    @State private var autoscrollSpeed: CGFloat?
    @State private var filterBarHeight: CGFloat = 28
    @State private var listScroller = ListScroller()
    private static let autoscrollBandHeight: CGFloat = 24
    /// 끄는 동안 커서가 올라가 있는 놓기 대상과 그곳에 놓으면 들어갈 곳(#109). 목록 빈 곳은 `nil` 키.
    @State private var dropHovers: [UUID?: MediaDropTarget] = [:]

    var body: some View {
        let project = editor.project
        let isRenamingFolder = Binding<Bool>(
            get: { renamingFolderID != nil },
            set: {
                if !$0 {
                    renamingFolderID = nil
                }
            }
        )
        let isEditingTags = Binding<Bool>(
            get: { tagEditingAssetID != nil },
            set: {
                if !$0 {
                    tagEditingAssetID = nil
                }
            }
        )

        let listOrder = project.assetListOrder
        panelList
            .alert("태그 편집", isPresented: isEditingTags) {
                TextField("인터뷰, B컷", text: $tagText)
                Button("저장") {
                    if let tagEditingAssetID {
                        editor.setTags(from: tagText, for: tagEditingAssetID)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("태그는 쉼표로 나눠 입력하세요.")
            }
            .alert("폴더 이름", isPresented: isRenamingFolder) {
                TextField("폴더 이름", text: $folderNameText)
                Button("확인") {
                    if let renamingFolderID {
                        editor.renameFolder(renamingFolderID, to: folderNameText)
                    }
                }
                Button("취소", role: .cancel) {}
            }
            // 이름 바꾸기는 하나만 골랐을 때만 한다. 고른 것이 폴더면 폴더 이름을 바꾼다(#107).
            .focusedSceneValue(\.renameSelectedAsset, listHasFocus ? singleSelection.map { id in { isFolder(id) ? beginRenamingFolder(id) : beginRenaming(id) } } : nil)
            .onChange(of: selectedAssetIDs, initial: true) { _, selection in
                selectionOrder = AssetSelectionOrder.updated(selectionOrder, selection: selection, listOrder: listOrder)
                // 타임라인의 "미디어 패널에서 원본 보기"처럼 접힌 폴더 안 원본이 골라지면 그 폴더들을 펼쳐 보이게 한다.
                for folderID in selection.flatMap(project.folderIDs(containing:)) where collapsedFolderIDs.contains(folderID) {
                    setExpanded(true, folderID)
                }
            }
            .focused($listHasFocus)
            .onChange(of: listHasFocus, initial: true) {
                isListFocused.wrappedValue = listHasFocus
            }
            // 목록에 포커스가 있을 때 ⌘X·⌘C·⌘V(편집 메뉴)는 원본을 잘라내고·복사하고·붙인다(#104). 타임라인 클립보드와 따로다.
            .onCutCommand {
                clipboardItems(for: selectedAssetIDs, isCut: true)
            }
            .onCopyCommand {
                clipboardItems(for: selectedAssetIDs, isCut: false)
            }
            .onPasteCommand(of: [.utf8PlainText]) { providers in
                let folderID = pasteTargetFolder
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let text = object as? String else { return }
                        DispatchQueue.main.async { paste(text, into: folderID) }
                    }
                }
            }
            // 목록에 포커스가 있을 때 ⌫(편집 > 삭제)로 고른 원본·폴더를 지운다. 이름을 바꾸는 중에는 글자를 지운다.
            .onDeleteCommand {
                if !selectedAssetIDs.isEmpty, renamingAssetID == nil {
                    let folderIDs = selectedAssetIDs.filter(isFolder)
                    let assetIDs = selectedAssetIDs.subtracting(folderIDs)
                    deleteFolders(folderIDs)
                    if !assetIDs.isEmpty {
                        requestDeletion(assetIDs)
                    }
                }
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: {
                        if !$0 {
                            pendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    if let pendingDeletion {
                        delete(pendingDeletion)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(deletionMessage)
            }
    }

    /// 폴더 트리 목록과 검색·필터·우클릭 메뉴. 본문 식이 길어 타입 검사가 느려지지 않도록 나눈다.
    private var panelList: some View {
        let project = editor.project
        // 거르는 중이면 그 아래 어딘가에 맞는 원본이 있는 폴더만 보이고, 아니면 빈 폴더도 보여 놓을 곳이 된다.
        let rootFolders = project.subfolders(of: nil).filter(isVisible)
        let rootAssets = project.unfiledAssets.filter(filter.matches)
        let hasNoResults = !project.assets.contains(where: filter.matches)

        return ScrollViewReader { proxy in
            List(selection: $selectedAssetIDs) {
                ForEach(rootFolders) { folder in
                    folderNode(folder)
                }
                ForEach(rootAssets) { asset in
                    assetRow(asset, folderID: nil)
                }
            }
            .onChange(of: revealRequest) { _, request in
                guard let request else { return }
                listHasFocus = true
                // 접힌 폴더가 펼쳐져 줄이 생긴 뒤에 스크롤한다.
                Task { @MainActor in
                    withAnimation { proxy.scrollTo(request.assetID, anchor: .center) }
                }
            }
        }
        // 행이 없는 빈 곳에 놓으면 맨 위로 옮긴다.
        .dropDestination(for: String.self) { items, _ in
            moveDropped(items, toFolder: nil)
        } isTargeted: { isTargeted in
            setDropHover(isTargeted, from: nil, to: .root)
        }
        // 맨 위로 옮겨질 때는 목록 테두리를 강조한다(#109).
        .overlay {
            if dropTarget == .root {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .task(id: dropHoverFolderID) {
            guard let folderID = dropHoverFolderID else { return }
            try? await Task.sleep(for: Self.dropHoverExpandDelay)
            if !Task.isCancelled, dropHoverFolderID == folderID {
                setExpanded(true, folderID)
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: MediaAsset.ID.self) { assetIDs in
            if assetIDs.isEmpty {
                // 목록 빈 곳(#104): 맨 위에 새 폴더·가져오기·붙여넣기.
                Button("새 폴더") { addFolder(in: nil) }
                Button("가져오기…") { importMedia() }
                    .keyboardShortcut("i", modifiers: .command)
                Divider()
                pasteButton(into: nil)
            } else {
                // 폴더 ID도 UUID라 폴더 줄을 우클릭하면 여기로 온다. 폴더 머리의 메뉴보다 이 메뉴가 먼저 뜨므로 폴더 메뉴를 여기서 낸다(#107).
                let folderIDs = assetIDs.filter(isFolder)
                if folderIDs.count == assetIDs.count {
                    folderMenu(for: folderIDs)
                } else {
                    assetMenu(for: assetIDs.subtracting(folderIDs))
                }
            }
        } primaryAction: { assetIDs in
            // 두 번 누르면 영상·오디오는 클립 편집 창을, 이미지는 훑어보기(Quick Look)를 연다(#81).
            if let assetID = assetIDs.first {
                if editor.asset(id: assetID)?.isTrimmable == true {
                    openClipEditor(assetID)
                } else {
                    openAsset(assetID)
                }
            }
        }
        .searchable(text: $filter.query, placement: .sidebar, prompt: "이름·태그 검색")
        // 검색창 바로 아래에 색상 레이블 필터를 둔다.
        .safeAreaInset(edge: .top) {
            MediaFilterBar(filter: $filter) {
                // 폴더 하나를 골랐으면 그 안에, 원본 하나를 골랐으면 그 원본이 있는 폴더 안에, 아니면 맨 위에 만든다.
                addFolder(in: singleSelection.flatMap(folder(containing:)))
            }
            // 끄는 동안 필터 줄에 커서를 대면 목록을 위로 굴린다(#108).
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
            .onDrop(of: [.item], delegate: AutoscrollDropDelegate(direction: -1, height: filterBarHeight) { autoscrollSpeed = $0 })
        }
        // 끄는 동안 목록 아래 끝 띠에 커서를 대면 목록을 아래로 굴린다(#108). 놓을 곳 안내 글자도 이 띠에 보인다(#109).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: Self.autoscrollBandHeight)
                .overlay {
                    if let dropTargetText {
                        Text(dropTargetText)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 12)
                    }
                }
                .contentShape(Rectangle())
                .onDrop(of: [.item], delegate: AutoscrollDropDelegate(direction: 1, height: Self.autoscrollBandHeight) { autoscrollSpeed = $0 })
        }
        .background(ListScrollerAnchor(scroller: listScroller))
        .task(id: autoscrollSpeed == nil) {
            while let speed = autoscrollSpeed, !Task.isCancelled {
                listScroller.scroll(by: speed)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .overlay {
            if hasNoResults, filter != MediaFilter() {
                ContentUnavailableView("일치하는 원본 없음", systemImage: "magnifyingglass", description: Text("검색어나 필터를 바꿔 보세요"))
            }
        }
    }

    // MARK: - Deletion

    /// 타임라인에서 쓰이지 않으면 바로 지우고, 쓰이면 함께 지워질 클립을 알리고 확인을 받는다.
    private func requestDeletion(_ assetIDs: Set<MediaAsset.ID>) {
        if editor.clipUsage(of: assetIDs).clipCount == 0 {
            delete(assetIDs)
        } else {
            pendingDeletion = assetIDs
        }
    }

    /// 원본과 그 클립을 지운다(실행 취소 가능). 디스크의 원본 파일은 두고, 앱 캐시인 프록시만 지운다.
    private func delete(_ assetIDs: Set<MediaAsset.ID>) {
        for asset in editor.project.assets where assetIDs.contains(asset.id) {
            ProxyGenerator.shared.removeProxy(for: asset)
        }
        editor.deleteAssets(assetIDs)
        selectedAssetIDs.subtract(assetIDs)
        pendingDeletion = nil
    }

    private var deletionTitle: String {
        guard let pendingDeletion else { return "" }
        let names = editor.project.assets.filter { pendingDeletion.contains($0.id) }.map(\.name)
        return names.count == 1 ? "\"\(names[0])\" 원본을 삭제하시겠습니까?" : "원본 \(names.count)개를 삭제하시겠습니까?"
    }

    private var deletionMessage: String {
        guard let pendingDeletion else { return "" }
        let usage = editor.clipUsage(of: pendingDeletion)
        let sequences = usage.sequenceNames.map { "\"\($0)\"" }.joined(separator: ", ")
        return "이 원본을 쓰는 클립 \(usage.clipCount)개(시퀀스 \(sequences))도 함께 지워집니다. 클립이 있던 자리는 빈 채로 남습니다. 원본 파일은 디스크에 그대로 남고, 실행 취소(⌘Z)로 되돌릴 수 있습니다."
    }

    /// 타임라인에 놓으면 클립이 되고, 다른 원본 위에 놓으면 그 원본이 있는 폴더로 옮긴다(목록은 이름순이라 자리는 정하지 않는다). 원본 ID만 문자열로 보낸다.
    private func assetRow(_ asset: MediaAsset, folderID: MediaFolder.ID?) -> some View {
        MediaAssetRow(asset: asset) { nameView(for: asset) }
            // 고른 원본 중 하나를 끌면 고른 원본 전체를 고른 순서대로, 고르지 않은 원본을 끌면 그 원본만 끈다(#86).
            .draggable(AssetDragPayload.encode(draggedAssetIDs(startingAt: asset.id)))
            .dropDestination(for: String.self) { items, _ in
                moveDropped(items, toFolder: folderID)
            } isTargeted: { isTargeted in
                // 원본 위에 놓아도 들어가는 곳은 그 원본의 폴더라, 그 폴더(맨 위면 목록)를 표시한다(#109).
                setDropHover(isTargeted, from: asset.id, to: folderID.map(MediaDropTarget.folder) ?? .root)
            }
    }

    /// 폴더 한 칸: 머리(펼침 삼각형)와 안의 하위 폴더·원본. 하위 폴더도 같은 모양이라 스스로를 부른다.
    private func folderNode(_ folder: MediaFolder) -> AnyView {
        let project = editor.project
        let subfolders = project.subfolders(of: folder.id).filter(isVisible)
        let assets = project.assets(in: folder).filter(filter.matches)
        return AnyView(
            DisclosureGroup(isExpanded: expansion(of: folder.id)) {
                ForEach(subfolders) { subfolder in
                    folderNode(subfolder)
                }
                ForEach(assets) { asset in
                    assetRow(asset, folderID: folder.id)
                }
            } label: {
                folderHeader(folder)
            }
        )
    }

    private func isVisible(_ folder: MediaFolder) -> Bool {
        filter == MediaFilter() || editor.project.folderContainsAsset(folder.id, matching: filter.matches)
    }

    // MARK: - Expansion

    private var collapsedFolderIDs: Set<MediaFolder.ID> {
        Set(collapsedFolderText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    /// 거르는 중에는 맞는 원본이 보이도록 모두 펼친다(접힌 상태는 그대로 기억한다).
    private func expansion(of folderID: MediaFolder.ID) -> Binding<Bool> {
        Binding(
            get: { filter != MediaFilter() || !collapsedFolderIDs.contains(folderID) },
            set: { isExpanded in
                if filter == MediaFilter() {
                    setExpanded(isExpanded, folderID)
                }
            }
        )
    }

    private func setExpanded(_ isExpanded: Bool, _ folderID: MediaFolder.ID) {
        var collapsed = collapsedFolderIDs
        if isExpanded {
            collapsed.remove(folderID)
        } else {
            collapsed.insert(folderID)
        }
        collapsedFolderText = collapsed.map(\.uuidString).sorted().joined(separator: ",")
    }

    /// 새 폴더를 `parentID` 안(`nil`이면 맨 위)에 만들고 그 폴더가 보이게 펼친 뒤 바로 이름을 정하게 한다.
    private func addFolder(in parentID: MediaFolder.ID?) {
        let folderID = editor.addFolder(named: "", in: parentID)
        if let parentID {
            setExpanded(true, parentID)
        }
        folderNameText = editor.project.folders.first { $0.id == folderID }?.name ?? ""
        renamingFolderID = folderID
    }

    /// 목록은 폴더 줄도 고른다. 폴더 ID도 `UUID`라 원본과 같은 선택에 들어온다(#107).
    private func isFolder(_ id: UUID) -> Bool {
        editor.project.folders.contains { $0.id == id }
    }

    /// 고른 것이 폴더면 그 폴더, 원본이면 그 원본이 있는 폴더(맨 위면 `nil`).
    private func folder(containing id: UUID) -> MediaFolder.ID? {
        isFolder(id) ? id : editor.project.folders.first { $0.assetIDs.contains(id) }?.id
    }

    /// 폴더 우클릭 메뉴. 하나면 새 폴더(그 안)·붙여넣기·이름 변경·삭제, 여럿이면 삭제만.
    @ViewBuilder
    private func folderMenu(for folderIDs: Set<MediaFolder.ID>) -> some View {
        if folderIDs.count == 1, let folderID = folderIDs.first {
            Button("새 폴더") { addFolder(in: folderID) }
            pasteButton(into: folderID)
            Divider()
            Button("폴더 이름 변경…") { beginRenamingFolder(folderID) }
        }
        Button("폴더 삭제") { deleteFolders(folderIDs) }
    }

    private func beginRenamingFolder(_ folderID: MediaFolder.ID) {
        folderNameText = editor.project.folders.first { $0.id == folderID }?.name ?? ""
        renamingFolderID = folderID
    }

    /// 안의 원본과 하위 폴더는 한 단계 위로 올라가고, 실행 취소(⌘Z)로 되돌릴 수 있어 확인 창을 띄우지 않는다.
    private func deleteFolders(_ folderIDs: Set<MediaFolder.ID>) {
        for folderID in folderIDs {
            editor.deleteFolder(folderID)
        }
        selectedAssetIDs.subtract(folderIDs)
    }

    /// 폴더 머리. 원본·폴더를 끌어다 놓으면 이 폴더 안으로 넣고, 끄는 동안 잠시 머물면 펼친다.
    /// 머리를 끌면 폴더째 옮기고, 우클릭으로 하위 폴더를 만들거나 이름을 바꾸거나 지운다.
    private func folderHeader(_ folder: MediaFolder) -> some View {
        let isDropTarget = dropTarget == .folder(folder.id)
        return Label(folder.name, systemImage: isDropTarget ? "folder.fill" : "folder")
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 끄는 동안 이 폴더 안으로 들어갈 곳이면 머리를 칠한다(#109).
            .background {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.3))
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .draggable(FolderDragPayload.encode(folder.id))
            .dropDestination(for: String.self) { items, _ in
                dropHoverFolderID = nil
                return moveDropped(items, toFolder: folder.id)
            } isTargeted: { isTargeted in
                setDropHover(isTargeted, from: folder.id, to: .folder(folder.id))
                if isTargeted {
                    dropHoverFolderID = folder.id
                } else if dropHoverFolderID == folder.id {
                    dropHoverFolderID = nil
                }
            }
            .contextMenu {
                folderMenu(for: [folder.id])
            }
    }

    // MARK: - Drop target

    /// 커서가 놓기 대상(폴더 머리·원본 줄, 목록 빈 곳은 `nil`) 위에 있음을 적거나 지운다(#109).
    /// 줄을 옮겨 갈 때 들어가기·나가기 알림 순서가 섞여도 지워지지 않도록 대상마다 따로 적는다.
    private func setDropHover(_ isTargeted: Bool, from source: UUID?, to target: MediaDropTarget) {
        dropHovers[source] = isTargeted ? target : nil
    }

    /// 지금 놓으면 들어갈 곳. 줄 위면 그 줄이 정한 곳이, 줄이 없는 빈 곳이면 맨 위다.
    private var dropTarget: MediaDropTarget? {
        dropHovers.first { $0.key != nil }?.value ?? dropHovers[UUID?.none]
    }

    private var dropTargetText: String? {
        switch dropTarget {
        case .root:
            "맨 위로 이동"
        case let .folder(folderID):
            "'\(editor.project.folders.first { $0.id == folderID }?.name ?? "")' 폴더로 이동"
        case nil:
            nil
        }
    }

    /// 하나만 골랐을 때의 그 원본. 이름 바꾸기·태그·클립 편집처럼 원본 하나에만 하는 일에 쓴다.
    private var singleSelection: MediaAsset.ID? {
        selectedAssetIDs.count == 1 ? selectedAssetIDs.first : nil
    }

    /// `assetID`를 끌 때 함께 끌 원본들.
    private func draggedAssetIDs(startingAt assetID: MediaAsset.ID) -> [MediaAsset.ID] {
        guard selectedAssetIDs.contains(assetID), selectedAssetIDs.count > 1 else { return [assetID] }
        // 함께 고른 폴더는 원본이 아니므로 빼고 끈다(#107).
        return selectionOrder.filter { selectedAssetIDs.contains($0) && !isFolder($0) }
    }

    /// 메뉴가 받은 원본들을 고른 순서대로(순서를 모르면 목록 순서).
    private func ordered(_ assetIDs: Set<MediaAsset.ID>) -> [MediaAsset.ID] {
        AssetSelectionOrder.ordered(assetIDs, by: selectionOrder, listOrder: editor.project.assetListOrder)
    }

    /// 놓은 원본·폴더를 `folderID` 폴더 안(`nil`이면 맨 위)으로 옮긴다. Finder에서 끈 파일은 가져온다.
    /// 폴더를 자기 자신이나 자기 아래로 놓으면 옮기지 않는다.
    private func moveDropped(_ items: [String], toFolder folderID: MediaFolder.ID?) -> Bool {
        dropHovers = [:]
        let fileURLs = items.compactMap(URL.init(string:)).filter(\.isFileURL)
        if !fileURLs.isEmpty {
            importFiles(fileURLs)
            return true
        }
        let folderIDs = items.flatMap(FolderDragPayload.decode)
        for draggedFolderID in Set(folderIDs) {
            editor.moveFolder(draggedFolderID, into: folderID)
        }
        if let folderID, !folderIDs.isEmpty {
            setExpanded(true, folderID)
        }
        let assetIDs = items.flatMap(AssetDragPayload.decode)
        if !assetIDs.isEmpty {
            editor.moveAssets(assetIDs, toFolder: folderID)
        }
        return !folderIDs.isEmpty || !assetIDs.isEmpty
    }

    @ViewBuilder
    private func nameView(for asset: MediaAsset) -> some View {
        if asset.id == renamingAssetID {
            TextField("이름", text: $renameText)
                .textFieldStyle(.plain)
                .focused($isRenameFieldFocused)
                .onAppear { isRenameFieldFocused = true }
                .onSubmit(commitRename)
                .onExitCommand { renamingAssetID = nil }
                // 다른 곳을 누르는 등 입력란에서 벗어나면 Finder처럼 입력한 이름으로 확정한다.
                .onChange(of: isRenameFieldFocused) { _, isFocused in
                    if !isFocused {
                        commitRename()
                    }
                }
        } else {
            Text(asset.name)
                .lineLimit(1)
        }
    }

    private func beginRenaming(_ assetID: MediaAsset.ID) {
        renameText = editor.asset(id: assetID)?.name ?? ""
        renamingAssetID = assetID
    }

    private func commitRename() {
        guard let renamingAssetID else { return }
        editor.renameAsset(renamingAssetID, to: renameText)
        self.renamingAssetID = nil
    }

    @ViewBuilder
    private func assetMenu(for assetIDs: Set<MediaAsset.ID>) -> some View {
        // 우클릭한 원본이 있는 폴더(맨 위면 맨 위)에 새 폴더를 만들고 붙인다(#104).
        let folderID = ordered(assetIDs).first.flatMap { assetID in editor.project.folders.first { $0.assetIDs.contains(assetID) }?.id }
        Button("새 폴더") { addFolder(in: folderID) }
        Divider()
        Button("잘라내기") { putOnClipboard(assetIDs, isCut: true) }
            .keyboardShortcut("x", modifiers: .command)
        Button("복사") { putOnClipboard(assetIDs, isCut: false) }
            .keyboardShortcut("c", modifiers: .command)
        pasteButton(into: folderID)
        Divider()
        Menu("색상 레이블") {
            Button("없음") {
                editor.setColorLabel(nil, for: assetIDs)
            }
            Divider()
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Button {
                    editor.setColorLabel(label, for: assetIDs)
                } label: {
                    Label(label.title, systemImage: "circle.fill")
                        .tint(label.color)
                }
            }
        }
        // 이름과 태그는 원본마다 다르므로 하나를 골랐을 때만 편집한다.
        if assetIDs.count == 1, let assetID = assetIDs.first, let asset = editor.asset(id: assetID), asset.isTrimmable {
            Button(ShortcutGuide.clipEditor.title) { openClipEditor(assetID) }
                .keyboardShortcut("t", modifiers: .command)
            // 두 번 누르기가 클립 편집 창을 열므로 원본 파일 전체는 여기서 훑어본다.
            Button("훑어보기") { openAsset(assetID) }
            Divider()
        }
        if assetIDs.count == 1, let assetID = assetIDs.first {
            Button("이름 변경") {
                beginRenaming(assetID)
            }
            // 메뉴 오른쪽에 단축키를 보여준다. 실제 단축키는 편집 메뉴의 "원본 이름 변경"이 맡는다.
            .keyboardShortcut(.f2, modifiers: [])
            Button("태그 편집…") {
                tagText = editor.asset(id: assetID)?.tags.joined(separator: ", ") ?? ""
                tagEditingAssetID = assetID
            }
        }
        let videos = assetIDs.compactMap { editor.asset(id: $0) }.filter { $0.kind == .video }
        if !videos.isEmpty {
            Divider()
            Button("프록시 만들기") { videos.forEach(ProxyGenerator.shared.generate(for:)) }
                .disabled(videos.allSatisfy { ProxyGenerator.shared.hasProxy($0) })
            Button("프록시 삭제") { videos.forEach(ProxyGenerator.shared.removeProxy(for:)) }
                .disabled(!videos.contains { ProxyGenerator.shared.hasProxy($0) || ProxyGenerator.shared.progress[$0.mediaKey] != nil })
            Divider()
        }
        Divider()
        // 메뉴 오른쪽에 단축키를 보여준다. 실제 ⌫는 목록에 포커스가 있을 때 처리한다.
        Button("삭제…", role: .destructive) { requestDeletion(assetIDs) }
            .keyboardShortcut(.delete, modifiers: [])
    }

    // MARK: - Clipboard

    /// 잘라내기·복사한 원본을 고른 순서대로 클립보드 글자로 담는다(#104). 편집 메뉴(⌘X·⌘C)가 클립보드에 쓴다.
    /// 함께 고른 폴더는 담지 않는다(#107).
    private func clipboardItems(for selection: Set<MediaAsset.ID>, isCut: Bool) -> [NSItemProvider] {
        let assetIDs = selection.filter { !isFolder($0) }
        guard !assetIDs.isEmpty, renamingAssetID == nil else { return [] }
        return [NSItemProvider(object: AssetClipboardPayload.encode(ordered(assetIDs), isCut: isCut) as NSString)]
    }

    /// 우클릭 메뉴의 잘라내기·복사. 편집 메뉴와 같은 글자를 클립보드에 쓴다.
    private func putOnClipboard(_ assetIDs: Set<MediaAsset.ID>, isCut: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AssetClipboardPayload.encode(ordered(assetIDs), isCut: isCut), forType: .string)
    }

    /// 우클릭 메뉴의 붙여넣기. 미디어 패널에서 잘라내거나 복사한 원본이 없으면 꺼진다.
    private func pasteButton(into folderID: MediaFolder.ID?) -> some View {
        let text = NSPasteboard.general.string(forType: .string)
        return Button("붙여넣기") {
            if let text {
                paste(text, into: folderID)
            }
        }
        .keyboardShortcut("v", modifiers: .command)
        .disabled(text.flatMap(AssetClipboardPayload.decode) == nil)
    }

    /// ⌘V로 붙일 곳: 폴더 하나를 골랐으면 그 폴더 안(#107), 아니면 고른 원본(목록 순서로 첫 원본)이 있는 폴더, 고른 것이 없으면 맨 위.
    private var pasteTargetFolder: MediaFolder.ID? {
        if let selected = singleSelection, isFolder(selected) {
            return selected
        }
        let first = editor.project.assetListOrder.first(where: selectedAssetIDs.contains)
        return first.flatMap { assetID in editor.project.folders.first { $0.assetIDs.contains(assetID) }?.id }
    }

    /// 복사한 원본은 사본을 만들고(같은 파일, 이름 뒤에 (1)·(2)…), 잘라낸 원본은 옮긴 뒤 클립보드를 비운다. 붙인 원본을 고른다.
    private func paste(_ text: String, into folderID: MediaFolder.ID?) {
        guard let content = AssetClipboardPayload.decode(text) else { return }
        let assetIDs = content.assetIDs.filter { editor.asset(id: $0) != nil }
        guard !assetIDs.isEmpty else { return }
        if content.isCut {
            editor.moveAssets(assetIDs, toFolder: folderID)
            NSPasteboard.general.clearContents()
            selectedAssetIDs = Set(assetIDs)
        } else {
            selectedAssetIDs = Set(editor.duplicateAssets(assetIDs, toFolder: folderID))
        }
        if let folderID {
            setExpanded(true, folderID)
        }
    }
}

/// 미디어 패널에서 끌어 놓으면 들어갈 곳(#109).
private enum MediaDropTarget: Equatable {
    /// 어느 폴더에도 없는 맨 위.
    case root
    case folder(MediaFolder.ID)
}

/// 끄는 동안 목록 끝 띠에 커서가 들어오면 그쪽으로 굴릴 속도를 알린다(#108). 띠의 바깥 끝에 가까울수록 빠르다.
/// 띠에 놓으면 아무 일도 하지 않는다.
private struct AutoscrollDropDelegate: DropDelegate {
    /// 위(-1)·아래(1).
    let direction: CGFloat
    let height: CGFloat
    let setSpeed: (CGFloat?) -> Void

    private func speed(at location: CGPoint) -> CGFloat {
        let fraction = height > 0 ? location.y / height : 0
        let depth = min(max(direction < 0 ? 1 - fraction : fraction, 0), 1)
        return direction * (4 + 16 * depth)
    }

    func validateDrop(info _: DropInfo) -> Bool {
        true
    }

    func dropEntered(info: DropInfo) {
        setSpeed(speed(at: info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        setSpeed(speed(at: info.location))
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info _: DropInfo) {
        setSpeed(nil)
    }

    func performDrop(info _: DropInfo) -> Bool {
        setSpeed(nil)
        return false
    }
}

/// 목록의 `NSScrollView`를 점 단위로 굴린다(#108). SwiftUI 목록은 줄 단위로만 스크롤할 수 있어 AppKit 스크롤 뷰를 직접 움직인다.
private final class ListScroller {
    /// 목록 뒤에 깐 빈 뷰. 이 뷰 가운데를 품은 가장 안쪽 스크롤 뷰가 목록이다.
    weak var anchor: NSView?
    private weak var scrollView: NSScrollView?

    /// 아래로 양수, 위로 음수. 목록 끝을 넘지 않는다.
    func scroll(by delta: CGFloat) {
        guard let scrollView = scrollView ?? findScrollView() else { return }
        self.scrollView = scrollView
        let clip = scrollView.contentView
        var bounds = clip.bounds
        bounds.origin.y += clip.isFlipped ? delta : -delta
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func findScrollView() -> NSScrollView? {
        guard let anchor, let root = anchor.window?.contentView else { return nil }
        let center = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        return Self.innermostScrollView(in: root, containing: center)
    }

    private static func innermostScrollView(in view: NSView, containing point: NSPoint) -> NSScrollView? {
        guard !view.isHidden, view.convert(view.bounds, to: nil).contains(point) else { return nil }
        for subview in view.subviews.reversed() {
            if let found = innermostScrollView(in: subview, containing: point) {
                return found
            }
        }
        return view as? NSScrollView
    }
}

private struct ListScrollerAnchor: NSViewRepresentable {
    let scroller: ListScroller

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        scroller.anchor = nsView
    }
}

private struct MediaFilterBar: View {
    @Binding var filter: MediaFilter
    let addFolder: () -> Void

    var body: some View {
        HStack {
            Menu {
                Section("색상 레이블") {
                    ForEach(ColorLabel.allCases, id: \.self) { label in
                        Toggle(label.title, isOn: Binding(
                            get: { filter.colorLabels.contains(label) },
                            set: { isOn in
                                if isOn {
                                    filter.colorLabels.insert(label)
                                } else {
                                    filter.colorLabels.remove(label)
                                }
                            }
                        ))
                    }
                }
            } label: {
                Label(
                    "필터",
                    systemImage: !filter.colorLabels.isEmpty
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help(ShortcutGuide.filterMedia.helpText)

            Spacer()

            if !filter.colorLabels.isEmpty {
                Button("필터 지우기") {
                    filter.colorLabels = []
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Button(action: addFolder) {
                Label("새 폴더", systemImage: "folder.badge.plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("새 폴더 — 원본을 분류할 폴더를 만듭니다(원본 하나를 골랐으면 그 원본이 있는 폴더 안에). 폴더 우클릭 > 새 폴더로 하위 폴더를 만듭니다")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

private struct MediaAssetRow<Name: View>: View {
    let asset: MediaAsset
    /// 이름 자리. 이름을 바꾸는 중이면 입력란이 들어온다.
    @ViewBuilder let name: Name

    var body: some View {
        // 이미지는 길이가 없어(타임라인에 놓을 기본 길이만 있음) 길이 대신 종류를 보여준다.
        // 파생 항목(#81)은 쓰는 구간 길이(뺀 구간이 있으면 남은 구간 길이의 합, #99)를 보여준다.
        let durationText = asset.kind == .image
            ? "이미지"
            : Duration.seconds(asset.placementDuration.seconds).formatted(.time(pattern: .minuteSecond))
        let showsProxyBadge = ProxyGenerator.shared.progress[asset.mediaKey] == nil && ProxyGenerator.shared.hasProxy(asset)

        // 간격을 정하지 않으면 뱃지 유무에 따라 썸네일과 이름 사이 여백이 달라진다(#83).
        HStack(spacing: 8) {
            MediaThumbnailView(asset: asset)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    if let colorLabel = asset.colorLabel {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(colorLabel.color)
                            .accessibilityLabel(colorLabel.title)
                    }
                    name
                }
                Text(detailText(durationText: durationText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                // 프록시를 만드는 중이면 진행률을, 다 만들었으면 표시를 보여준다(#43).
                if let fraction = ProxyGenerator.shared.progress[asset.mediaKey] {
                    ProgressView(value: fraction) {
                        Text("프록시 만드는 중")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.mini)
                }
                // 파생 항목(#81)과 프록시 표시는 한 줄에 둔다. 뱃지가 없으면 줄을 넣지 않는다.
                if asset.isDerived || showsProxyBadge {
                    HStack(spacing: 4) {
                        if asset.isDerived {
                            Text("파생")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .background(.yellow.opacity(0.3), in: Capsule())
                                .help("원본에서 트림한 항목입니다. 타임라인에 놓으면 이 구간만 들어가고, 원본 항목·파일은 그대로입니다")
                        }
                        if showsProxyBadge {
                            Text("프록시")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .background(.quaternary, in: Capsule())
                                .help("미리보기는 1080p 대체 파일로 재생하고, 내보내기는 원본으로 합니다")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 태그가 있으면 길이 뒤에 붙인다. 예: "0:10 · 인터뷰, B컷"
    /// 파생 항목은 길이 뒤에 쓰는 구간을, 구간을 뺐으면(#99) 남은 구간 수를, 태그가 있으면 그 뒤에 붙인다. 예: "0:05 · 0:02.0–0:07.0 · 구간 3개 · 인터뷰"
    private func detailText(durationText: String) -> String {
        let label = TimelineScale(pointsPerSecond: 40)
        let rangeText = asset.usedRange.map { "\(label.timeLabel(for: $0.start))–\(label.timeLabel(for: $0.end))" }
        let segmentText = asset.excludedRanges.isEmpty ? nil : "구간 \(asset.keptRanges.count)개"
        return ([durationText, rangeText, segmentText] + [asset.tags.isEmpty ? nil : asset.tags.joined(separator: ", ")]).compactMap(\.self).joined(separator: " · ")
    }
}

/// 영상은 한 장면, 이미지는 축소본을 보여준다. 만들지 못하면(오디오, 파일 없음) 종류별 아이콘을 둔다.
private struct MediaThumbnailView: View {
    let asset: MediaAsset
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: asset.id) {
            image = await MediaThumbnailProvider.shared.thumbnail(for: asset)
        }
    }

    private var fallbackSymbol: String {
        switch asset.kind {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        }
    }
}

#Preview {
    // 미리보기에서는 저장하지 않도록 메모리 안의 저장소를 쓴다.
    let container = try! ModelContainer(
        for: ProjectRecord.self, ProjectBackupRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    MediaPanelView(
        editor: ProjectEditor(project: SampleData.project, repository: SwiftDataProjectRepository(modelContext: container.mainContext)),
        selectedAssetIDs: .constant([]),
        openAsset: { _ in }
    )
}
