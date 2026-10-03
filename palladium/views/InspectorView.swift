import CoreMedia
import SwiftUI

/// 타임라인 클립을 선택할 수 없는 동안(#17 이전)에는 미디어 패널에서 고른 원본을 임시로 보여준다.
struct InspectorView: View {
    let asset: MediaAsset?
    @State private var selectedTab: InspectorTab = .trim

    var body: some View {
        if let asset {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(asset: asset)
                    .padding()

                Picker("속성", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)

                switch selectedTab {
                case .trim: TrimInspectorView(asset: asset)
                case .effect: EffectInspectorView()
                case .transform: TransformInspectorView()
                case .subtitle: SubtitleInspectorView()
                }
            }
        } else {
            ContentUnavailableView("선택한 원본 없음", systemImage: "slider.horizontal.3")
        }
    }
}

private enum InspectorTab: CaseIterable, Identifiable {
    case trim
    case effect
    case transform
    case subtitle

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .trim: "트림"
        case .effect: "이펙트"
        case .transform: "트랜스폼"
        case .subtitle: "자막"
        }
    }
}

private struct InspectorHeader: View {
    let asset: MediaAsset

    var body: some View {
        let durationText = Duration.seconds(asset.duration.seconds).formatted(.time(pattern: .minuteSecond))

        VStack(alignment: .leading) {
            Text(asset.name)
                .font(.headline)
                .lineLimit(1)
            Text("\(kindTitle) · \(durationText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var kindTitle: String {
        switch asset.kind {
        case .video: "영상"
        case .audio: "오디오"
        case .image: "이미지"
        }
    }
}

#Preview("원본 선택") {
    InspectorView(asset: SampleData.introVideo)
        .frame(width: 280, height: 500)
}

#Preview("선택 없음") {
    InspectorView(asset: nil)
        .frame(width: 280, height: 500)
}
