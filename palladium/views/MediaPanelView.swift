import CoreMedia
import SwiftUI

/// 프리미어 프로의 프로젝트 패널처럼 한 번 클릭은 선택만 하고, 더블클릭하면 원본을 미리보기(소스 모니터)에서 연다.
struct MediaPanelView: View {
    @Binding var project: Project
    @Binding var selectedAssetID: MediaAsset.ID?
    let openAsset: (MediaAsset.ID) -> Void
    @State private var filter = MediaFilter()
    /// 태그를 편집 중인 원본. 편집 창이 닫히면 `nil`.
    @State private var tagEditingAssetID: MediaAsset.ID?
    @State private var tagText = ""

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
                        ForEach(section.assets) { MediaAssetRow(asset: $0) }
                    }
                }
            }
            if !unfiledAssets.isEmpty {
                Section("분류 안 됨") {
                    ForEach(unfiledAssets) { MediaAssetRow(asset: $0) }
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
        // 검색창 바로 아래에 색상 레이블·별점 필터를 둔다.
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
        Menu("별점") {
            ForEach(0 ... MediaAsset.maximumRating, id: \.self) { stars in
                Button(stars == 0 ? "별점 없음" : String(repeating: "★", count: stars)) {
                    updateAssets(assetIDs) { $0.rate(stars) }
                }
            }
        }
        // 태그는 원본마다 다르므로 하나를 골랐을 때만 편집한다.
        if assetIDs.count == 1, let assetID = assetIDs.first {
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
                Picker("최소 별점", selection: $filter.minimumRating) {
                    Text("모든 별점").tag(0)
                    ForEach(1 ... MediaAsset.maximumRating, id: \.self) { stars in
                        Text("\(String(repeating: "★", count: stars)) 이상").tag(stars)
                    }
                }
            } label: {
                Label(
                    "필터",
                    systemImage: filter.hasAttributeConditions
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()

            Spacer()

            if filter.hasAttributeConditions {
                Button("필터 지우기") {
                    filter.colorLabels = []
                    filter.minimumRating = 0
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

private struct MediaAssetRow: View {
    let asset: MediaAsset

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
                    Text(asset.name)
                        .lineLimit(1)
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

    /// 길이 뒤에 별점과 태그가 있을 때만 붙인다. 예: "0:10 · ★★★ · 인터뷰, B컷"
    private func detailText(durationText: String) -> String {
        var parts = [durationText]
        if asset.rating > 0 {
            parts.append(String(repeating: "★", count: asset.rating))
        }
        if !asset.tags.isEmpty {
            parts.append(asset.tags.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
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
