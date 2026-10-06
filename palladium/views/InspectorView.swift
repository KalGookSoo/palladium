import CoreMedia
import SwiftUI

/// 프리미어 프로의 이펙트 컨트롤 패널처럼 타임라인에서 선택한 클립의 속성만 보여준다.
struct InspectorView: View {
    let clip: Clip?
    /// 선택한 클립이 참조하는 원본. 프로젝트에서 찾지 못하면 `nil`이다.
    let asset: MediaAsset?
    /// 여러 클립을 골랐으면 속성 대신 고른 개수를 보여준다.
    var selectedClipCount = 0
    /// `true`면 이름 칸에 포커스를 주고 `false`로 되돌린다(F2·우클릭 > 이름 변경).
    var isNameFocusRequested: Binding<Bool> = .constant(false)
    /// 클립 별칭(#78). 비우면 원본 이름을 보여준다.
    var renameClip: (Clip.ID, String) -> Void = { _, _ in }
    /// 트림 탭에서 원본 시작·끝 지점을 입력했을 때.
    var setClipSource: (Clip.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var setTransform: (Clip.ID, ClipTransform) -> Void = { _, _ in }
    var setClipAudio: (Clip.ID, Double, Bool) -> Void = { _, _, _ in }
    var setClipSpeed: (Clip.ID, Double) -> Void = { _, _ in }
    /// 고른 클립과 바로 앞 클립 사이 전환의 최대 길이. 맞닿은 앞 클립이 없으면 0이다.
    var maximumTransitionDuration = CMTime.zero
    var setTransition: (Clip.ID, ClipTransition?) -> Void = { _, _ in }
    var setAudioCrossfade: (Clip.ID, CMTime?) -> Void = { _, _ in }
    /// 자막 트랙에서 고른 자막. 있으면 클립 대신 자막 속성을 보여준다.
    var subtitle: Subtitle?
    var updateSubtitle: (Subtitle.ID, String, SubtitleStyle) -> Void = { _, _, _ in }
    var setSubtitleRange: (Subtitle.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var deleteSubtitle: (Subtitle.ID) -> Void = { _ in }
    /// 마스크 레인에서 고른 마스크(#59).
    var mask: Mask?
    var updateMask: (Mask) -> Void = { _ in }
    var setMaskRange: (Mask.ID, CMTime, CMTime) -> Void = { _, _, _ in }
    var deleteMask: (Mask.ID) -> Void = { _ in }
    @State private var selectedTab: InspectorTab = .trim

    var body: some View {
        if let subtitle {
            SubtitleInspectorView(
                subtitle: subtitle,
                update: { text, style in updateSubtitle(subtitle.id, text, style) },
                setRange: { start, end in setSubtitleRange(subtitle.id, start, end) },
                delete: { deleteSubtitle(subtitle.id) }
            )
            .id(subtitle.id)
        } else if let mask {
            MaskInspectorView(
                mask: mask,
                update: updateMask,
                setRange: { start, end in setMaskRange(mask.id, start, end) },
                delete: { deleteMask(mask.id) }
            )
        } else if let clip {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(clip: clip, asset: asset, isNameFocusRequested: isNameFocusRequested, rename: renameClip)
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
                    TrimInspectorView(
                        clip: clip,
                        sourceDuration: asset?.trimmableDuration,
                        setSource: { start, end in setClipSource(clip.id, start, end) },
                        setSpeed: asset?.kind == .image ? nil : { setClipSpeed(clip.id, $0) }
                    )
                case .audio:
                    if asset?.kind == .image {
                        ContentUnavailableView("이미지 클립", systemImage: "photo", description: Text("이미지 클립에는 소리가 없습니다"))
                    } else {
                        AudioInspectorView(clip: clip) { volume, isMuted in setClipAudio(clip.id, volume, isMuted) }
                    }
                case .effect: EffectInspectorView()
                case .transform:
                    // 소리만 있는 클립은 화면에 그리지 않는다.
                    if asset?.kind == .audio {
                        ContentUnavailableView("오디오 클립", systemImage: "waveform", description: Text("오디오 클립은 화면에 그리지 않습니다"))
                    } else {
                        TransformInspectorView(transform: clip.transform) { setTransform(clip.id, $0) }
                    }
                case .transition:
                    TransitionInspectorView(
                        clip: clip,
                        hasPicture: asset?.kind != .audio,
                        hasSound: asset?.kind != .image,
                        maximumDuration: maximumTransitionDuration,
                        setTransition: { setTransition(clip.id, $0) },
                        setAudioCrossfade: { setAudioCrossfade(clip.id, $0) }
                    )
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
                    description: Text("타임라인에서 클립·자막·마스크를 선택하세요")
                )
            }
        }
    }
}

private enum InspectorTab: CaseIterable, Identifiable {
    case trim
    case audio
    case effect
    case transform
    case transition

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .trim: "트림"
        case .audio: "오디오"
        case .effect: "이펙트"
        case .transform: "트랜스폼"
        case .transition: "전환"
        }
    }
}

/// 맨 위 이름 칸에서 클립 별칭을 바꾼다. 비어 있으면 원본 이름이 흐리게 보이고, Return·다른 곳 누르기로 확정, Esc로 취소한다.
private struct InspectorHeader: View {
    let clip: Clip
    let asset: MediaAsset?
    @Binding var isNameFocusRequested: Bool
    let rename: (Clip.ID, String) -> Void
    @State private var nameText = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        let durationText = Duration.seconds(clip.timelineDuration.seconds).formatted(.time(pattern: .minuteSecond))
        let assetName = asset?.name ?? "알 수 없는 원본"

        VStack(alignment: .leading) {
            TextField("클립 이름", text: $nameText, prompt: Text(assetName))
                .textFieldStyle(.plain)
                .font(.headline)
                .lineLimit(1)
                .focused($isNameFocused)
                .onSubmit { isNameFocused = false }
                .onExitCommand {
                    nameText = clip.name ?? ""
                    isNameFocused = false
                }
                // 다른 곳을 누르는 등 입력란에서 벗어나면 입력한 이름으로 확정한다(같으면 편집이 남지 않는다).
                .onChange(of: isNameFocused) { _, isFocused in
                    if !isFocused {
                        rename(clip.id, nameText)
                    }
                }
                .help("클립 이름 — 타임라인에서 쓰임새를 구분하는 별칭입니다. 비우면 원본 이름을 보여줍니다 (F2)")
            // 별칭이 있으면 원본 이름을 함께 보여준다.
            Text(clip.name == nil ? "\(kindTitle) 클립 · \(durationText)" : "원본: \(assetName) · \(kindTitle) 클립 · \(durationText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
        // 다른 클립을 고르거나 실행 취소로 별칭이 바뀌면 입력란도 따라간다.
        .onChange(of: clip.id, initial: true) { oldID, _ in
            // 입력하던 중 다른 클립을 고르면 입력한 이름은 원래 클립에 확정한다.
            if isNameFocused {
                rename(oldID, nameText)
            }
            nameText = clip.name ?? ""
        }
        .onChange(of: clip.name) { nameText = clip.name ?? "" }
        // 입력하던 중 선택이 풀려 머리말이 사라져도 입력한 이름을 확정한다.
        .onDisappear {
            if isNameFocused {
                rename(clip.id, nameText)
            }
        }
        .onChange(of: isNameFocusRequested, initial: true) {
            if isNameFocusRequested {
                isNameFocused = true
                isNameFocusRequested = false
            }
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
