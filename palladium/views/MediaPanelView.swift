import CoreMedia
import SwiftUI

/// 프리미어 프로의 프로젝트 패널처럼 한 번 클릭은 선택만 하고, 더블클릭하면 원본을 미리보기(소스 모니터)에서 연다.
/// 포토샵 레이어처럼 원본 이름을 목록에서 바로 바꿔 정리한다(F2 또는 우클릭 > 이름 변경).
struct MediaPanelView: View {
    @Binding var project: Project
    @Binding var selectedAssetID: MediaAsset.ID?
    let openAsset: (MediaAsset.ID) -> Void
    @State private var filter = MediaFilter()
    /// 태그를 편집 중인 원본. 편집 창이 닫히면 `nil`.
    @State private var tagEditingAssetID: MediaAsset.ID?
    @State private var tagText = ""
    /// 목록 안에서 이름을 바꾸는 중인 원본.
    @State private var renamingAssetID: MediaAsset.ID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        let folderSections = project.folders.map { folder in
            (folder: folder, assets: project.assets(in: folder).filter(filter.matches))
        }
        let unfiledAssets = project.unfiledAssets.filter(filter.matches)
        let hasNoResults = folderSections.allSatisfy(\.assets.isEmpty) && unfiledAssets.isEmpty
        let isEditingTags = Binding<Bool>(
            get: { tagEditingAssetID != nil },
            set: {
                if !$0 {
                    tagEditingAssetID = nil
                }
            }
        )

        List(selection: $selectedAssetID) {
            ForEach(folderSections, id: \.folder.id) { section in
                if !section.assets.isEmpty {
                    Section(section.folder.name) {
                        ForEach(section.assets) { asset in
                            MediaAssetRow(asset: asset) { nameView(for: asset) }
                        }
                    }
                }
            }
            if !unfiledAssets.isEmpty {
                Section("분류 안 됨") {
                    ForEach(unfiledAssets) { asset in
                        MediaAssetRow(asset: asset) { nameView(for: asset) }
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
            if let assetID = assetIDs.first {
                openAsset(assetID)
            }
        }
        .searchable(text: $filter.query, placement: .sidebar, prompt: "이름·태그 검색")
        // 검색창 바로 아래에 색상 레이블 필터를 둔다.
        .safeAreaInset(edge: .top) {
            MediaFilterBar(filter: $filter)
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
                    updateAssets([tagEditingAssetID]) { $0.setTags(from: tagText) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("태그는 쉼표로 나눠 입력하세요.")
        }
        .focusedSceneValue(\.renameSelectedAsset, selectedAssetID.map { assetID in { beginRenaming(assetID) } })
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
        renameText = project.assets.first { $0.id == assetID }?.name ?? ""
        renamingAssetID = assetID
    }

    private func commitRename() {
        guard let renamingAssetID else { return }
        updateAssets([renamingAssetID]) { $0.rename(to: renameText) }
        self.renamingAssetID = nil
    }

    @ViewBuilder
    private func assetMenu(for assetIDs: Set<MediaAsset.ID>) -> some View {
        Menu("색상 레이블") {
            Button("없음") {
                updateAssets(assetIDs) { $0.colorLabel = nil }
            }
            Divider()
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Button {
                    updateAssets(assetIDs) { $0.colorLabel = label }
                } label: {
                    Label(label.title, systemImage: "circle.fill")
                        .tint(label.color)
                }
            }
        }
        // 이름과 태그는 원본마다 다르므로 하나를 골랐을 때만 편집한다.
        if assetIDs.count == 1, let assetID = assetIDs.first {
            Button("이름 변경") {
                beginRenaming(assetID)
            }
            // 메뉴 오른쪽에 단축키를 보여준다. 실제 단축키는 편집 메뉴의 "원본 이름 변경"이 맡는다.
            .keyboardShortcut(.f2, modifiers: [])
            Button("태그 편집…") {
                tagText = project.assets.first { $0.id == assetID }?.tags.joined(separator: ", ") ?? ""
                tagEditingAssetID = assetID
            }
        }
    }

    private func updateAssets(_ assetIDs: Set<MediaAsset.ID>, _ change: (inout MediaAsset) -> Void) {
        for index in project.assets.indices where assetIDs.contains(project.assets[index].id) {
            change(&project.assets[index])
        }
    }
}

private struct MediaFilterBar: View {
    @Binding var filter: MediaFilter

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

            Spacer()

            if !filter.colorLabels.isEmpty {
                Button("필터 지우기") {
                    filter.colorLabels = []
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
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
        let durationText = Duration.seconds(asset.duration.seconds).formatted(.time(pattern: .minuteSecond))

        HStack {
            // 실제 썸네일은 미디어 가져오기(#1)에서 생성하고, 그전까지 종류별 아이콘으로 자리를 잡는다.
            Image(systemName: thumbnailSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
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
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 태그가 있으면 길이 뒤에 붙인다. 예: "0:10 · 인터뷰, B컷"
    private func detailText(durationText: String) -> String {
        asset.tags.isEmpty ? durationText : "\(durationText) · \(asset.tags.joined(separator: ", "))"
    }

    private var thumbnailSymbol: String {
        switch asset.kind {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        }
    }
}

#Preview {
    @Previewable @State var project = SampleData.project
    MediaPanelView(project: $project, selectedAssetID: .constant(nil), openAsset: { _ in })
}
