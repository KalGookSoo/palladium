import CoreMedia
import SwiftData
import SwiftUI

/// 프리미어 프로의 프로젝트 패널처럼 한 번 클릭은 선택만 하고, 더블클릭하면 원본을 미리보기(소스 모니터)에서 연다.
/// 포토샵 레이어처럼 원본 이름을 목록에서 바로 바꿔 정리한다(F2 또는 우클릭 > 이름 변경).
/// 폴더(한 단계)를 만들어 원본을 끌어다 넣거나 우클릭 > 폴더로 이동으로 분류한다. 원본은 한 폴더에만 속한다.
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

    var body: some View {
        let project = editor.project
        let folderSections = project.folders.map { folder in
            (folder: folder, assets: project.assets(in: folder).filter(filter.matches))
        }
        let unfiledAssets = project.unfiledAssets.filter(filter.matches)
        let hasNoResults = folderSections.allSatisfy(\.assets.isEmpty) && unfiledAssets.isEmpty
        // 거르는 중이 아니면 빈 폴더와 빈 "분류 안 됨"도 보여 원본을 끌어다 놓을 수 있게 한다.
        let isFiltering = filter != MediaFilter()
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

        let listOrder = folderSections.flatMap(\.assets).map(\.id) + unfiledAssets.map(\.id)

        List(selection: $selectedAssetIDs) {
            ForEach(folderSections, id: \.folder.id) { section in
                if !section.assets.isEmpty || !isFiltering {
                    Section {
                        ForEach(section.assets) { asset in
                            assetRow(asset, folderID: section.folder.id)
                        }
                    } header: {
                        folderHeader(section.folder)
                    }
                }
            }
            if !unfiledAssets.isEmpty || (!isFiltering && !project.folders.isEmpty) {
                Section {
                    ForEach(unfiledAssets) { asset in
                        assetRow(asset, folderID: nil)
                    }
                } header: {
                    Text("분류 안 됨")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            moveDroppedAssets(items, toFolder: nil, before: nil)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: MediaAsset.ID.self) { assetIDs in
            if !assetIDs.isEmpty {
                assetMenu(for: assetIDs)
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
                let folderID = editor.addFolder(named: "")
                // 만들자마자 이름을 정하게 한다.
                folderNameText = editor.project.folders.first { $0.id == folderID }?.name ?? ""
                renamingFolderID = folderID
            }
        }
        .overlay {
            if hasNoResults, filter != MediaFilter() {
                ContentUnavailableView("일치하는 원본 없음", systemImage: "magnifyingglass", description: Text("검색어나 필터를 바꿔 보세요"))
            }
        }
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
        // 이름 바꾸기는 하나만 골랐을 때만 한다.
        .focusedSceneValue(\.renameSelectedAsset, listHasFocus ? singleSelection.map { assetID in { beginRenaming(assetID) } } : nil)
        .onChange(of: selectedAssetIDs, initial: true) { _, selection in
            selectionOrder = AssetSelectionOrder.updated(selectionOrder, selection: selection, listOrder: listOrder)
        }
        .focused($listHasFocus)
        .onChange(of: listHasFocus, initial: true) {
            isListFocused.wrappedValue = listHasFocus
        }
        // 목록에 포커스가 있을 때 ⌫(편집 > 삭제)로 고른 원본을 지운다. 이름을 바꾸는 중에는 글자를 지운다.
        .onDeleteCommand {
            if !selectedAssetIDs.isEmpty, renamingAssetID == nil {
                requestDeletion(selectedAssetIDs)
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

    /// 타임라인에 놓으면 클립이 되고, 다른 원본 위에 놓으면 그 원본이 있는 폴더의 그 자리로 옮긴다. 원본 ID만 문자열로 보낸다.
    private func assetRow(_ asset: MediaAsset, folderID: MediaFolder.ID?) -> some View {
        MediaAssetRow(asset: asset) { nameView(for: asset) }
            // 고른 원본 중 하나를 끌면 고른 원본 전체를 고른 순서대로, 고르지 않은 원본을 끌면 그 원본만 끈다(#86).
            .draggable(AssetDragPayload.encode(draggedAssetIDs(startingAt: asset.id)))
            .dropDestination(for: String.self) { items, _ in
                moveDroppedAssets(items, toFolder: folderID, before: folderID == nil ? nil : asset.id)
            }
    }

    /// 폴더 머리. 원본을 끌어다 놓으면 폴더 끝에 넣고, 우클릭으로 이름을 바꾸거나 지운다.
    private func folderHeader(_ folder: MediaFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                moveDroppedAssets(items, toFolder: folder.id, before: nil)
            }
            .contextMenu {
                Button("폴더 이름 변경…") {
                    folderNameText = folder.name
                    renamingFolderID = folder.id
                }
                // 안의 원본은 "분류 안 됨"으로 돌아가고, 실행 취소(⌘Z)로 되돌릴 수 있어 확인 창을 띄우지 않는다.
                Button("폴더 삭제") { editor.deleteFolder(folder.id) }
            }
    }

    /// 하나만 골랐을 때의 그 원본. 이름 바꾸기·태그·클립 편집처럼 원본 하나에만 하는 일에 쓴다.
    private var singleSelection: MediaAsset.ID? {
        selectedAssetIDs.count == 1 ? selectedAssetIDs.first : nil
    }

    /// `assetID`를 끌 때 함께 끌 원본들.
    private func draggedAssetIDs(startingAt assetID: MediaAsset.ID) -> [MediaAsset.ID] {
        guard selectedAssetIDs.contains(assetID), selectedAssetIDs.count > 1 else { return [assetID] }
        return selectionOrder.filter(selectedAssetIDs.contains)
    }

    /// 메뉴가 받은 원본들을 고른 순서대로(순서를 모르면 목록 순서).
    private func ordered(_ assetIDs: Set<MediaAsset.ID>) -> [MediaAsset.ID] {
        let project = editor.project
        let listOrder = project.folders.flatMap { project.assets(in: $0).map(\.id) } + project.unfiledAssets.map(\.id)
        return AssetSelectionOrder.ordered(assetIDs, by: selectionOrder, listOrder: listOrder)
    }

    private func moveDroppedAssets(_ items: [String], toFolder folderID: MediaFolder.ID?, before beforeAssetID: MediaAsset.ID?) -> Bool {
        let fileURLs = items.compactMap(URL.init(string:)).filter(\.isFileURL)
        if !fileURLs.isEmpty {
            importFiles(fileURLs)
            return true
        }
        let assetIDs = items.flatMap(AssetDragPayload.decode).filter { $0 != beforeAssetID }
        guard !assetIDs.isEmpty else { return false }
        editor.moveAssets(assetIDs, toFolder: folderID, before: beforeAssetID)
        return true
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
        Divider()
        Menu("폴더로 이동") {
            Button("분류 안 됨") { editor.moveAssets(ordered(assetIDs), toFolder: nil) }
            Divider()
            ForEach(editor.project.folders) { folder in
                Button(folder.name) { editor.moveAssets(ordered(assetIDs), toFolder: folder.id) }
            }
        }
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
            .help("새 폴더 — 원본을 분류할 폴더를 만듭니다")
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
        // 파생 항목(#81)은 쓰는 구간 길이를 보여준다.
        let durationText = asset.kind == .image
            ? "이미지"
            : Duration.seconds((asset.usedRange?.duration ?? asset.duration).seconds).formatted(.time(pattern: .minuteSecond))
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
    /// 파생 항목은 길이 뒤에 쓰는 구간을, 태그가 있으면 그 뒤에 붙인다. 예: "0:05 · 0:02.0–0:07.0 · 인터뷰"
    private func detailText(durationText: String) -> String {
        let label = TimelineScale(pointsPerSecond: 40)
        let rangeText = asset.usedRange.map { "\(label.timeLabel(for: $0.start))–\(label.timeLabel(for: $0.end))" }
        return ([durationText, rangeText] + [asset.tags.isEmpty ? nil : asset.tags.joined(separator: ", ")]).compactMap(\.self).joined(separator: " · ")
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
