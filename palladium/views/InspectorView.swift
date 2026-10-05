import CoreMedia
import SwiftUI

/// 프리미어 프로의 이펙트 컨트롤 패널처럼 타임라인에서 선택한 클립의 속성만 보여준다.
struct InspectorView: View {
    let clip: Clip?
    /// 선택한 클립이 참조하는 원본. 프로젝트에서 찾지 못하면 `nil`이다.
    let asset: MediaAsset?
    /// 여러 클립을 골랐으면 속성 대신 고른 개수를 보여준다.
    var selectedClipCount = 0
    /// 트림 탭에서 원본 시작·끝 지점을 입력했을 때.
    var setClipSource: (Clip.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var setTransform: (Clip.ID, ClipTransform) -> Void = { _, _ in }
    @State private var selectedTab: InspectorTab = .trim

    var body: some View {
        if let clip {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(clip: clip, asset: asset)
                    .padding()

                Picker("속성", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // segmented Picker는 기본적으로 내용 폭만 차지하므로, 인스펙터 폭을 가득 채우도록 늘린다.
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                switch selectedTab {
                case .trim:
                    TrimInspectorView(clip: clip, sourceDuration: asset?.trimmableDuration) { start, end in
                        setClipSource(clip.id, start, end)
                    }
                case .effect: EffectInspectorView()
                case .transform:
                    // 소리만 있는 클립은 화면에 그리지 않는다.
                    if asset?.kind == .audio {
                        ContentUnavailableView("오디오 클립", systemImage: "waveform", description: Text("오디오 클립은 화면에 그리지 않습니다"))
                    } else {
                        TransformInspectorView(transform: clip.transform) { setTransform(clip.id, $0) }
                    }
                }
            }
        } else {
            if selectedClipCount > 1 {
                ContentUnavailableView(
                    "클립 \(selectedClipCount)개 선택",
                    systemImage: "square.stack",
                    description: Text("속성을 보려면 클립을 하나만 선택하세요")
                )
            } else {
                ContentUnavailableView(
                    "선택한 클립 없음",
                    systemImage: "slider.horizontal.3",
                    description: Text("타임라인에서 클립을 선택하세요")
                )
            }
        }
    }
}

private enum InspectorTab: CaseIterable, Identifiable {
    case trim
    case effect
    case transform

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .trim: "트림"
        case .effect: "이펙트"
        case .transform: "트랜스폼"
        }
    }
}

private struct InspectorHeader: View {
    let clip: Clip
    let asset: MediaAsset?

    var body: some View {
        let durationText = Duration.seconds(clip.sourceRange.duration.seconds).formatted(.time(pattern: .minuteSecond))

        VStack(alignment: .leading) {
            Text(asset?.name ?? "알 수 없는 원본")
                .font(.headline)
                .lineLimit(1)
            Text("\(kindTitle) 클립 · \(durationText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var kindTitle: String {
        switch asset?.kind {
        case .video: "영상"
        case .audio: "오디오"
        case .image: "이미지"
        case nil: "알 수 없는"
        }
    }
}

#Preview("클립 선택") {
    let clip = SampleData.videoTrack.clips[1]
    InspectorView(clip: clip, asset: SampleData.bRollVideo)
        .frame(width: 280, height: 500)
}

#Preview("선택 없음") {
    InspectorView(clip: nil, asset: nil)
        .frame(width: 280, height: 500)
}
