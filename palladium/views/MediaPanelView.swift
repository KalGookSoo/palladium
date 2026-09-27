import CoreMedia
import SwiftUI

struct MediaPanelView: View {
    let project: Project
    @Binding var selectedAssetID: MediaAsset.ID?
    @State private var searchQuery = ""

    var body: some View {
        let folderSections = project.folders.map { folder in
            (folder: folder, assets: project.assets(in: folder).filter { $0.matches(nameQuery: searchQuery) })
        }
        let unfiledAssets = project.unfiledAssets.filter { $0.matches(nameQuery: searchQuery) }
        let hasNoResults = folderSections.allSatisfy(\.assets.isEmpty) && unfiledAssets.isEmpty

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
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "이름 검색")
        .overlay {
            if hasNoResults, !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
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
                Text(asset.name)
                    .lineLimit(1)
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
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
    MediaPanelView(project: SampleData.project, selectedAssetID: .constant(nil))
}
