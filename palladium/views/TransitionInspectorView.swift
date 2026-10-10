import CoreMedia
import SwiftUI

/// 바로 앞 클립에서 이 클립으로 넘어가는 영상 전환과 오디오 크로스페이드(#8). 둘은 따로 정한다.
/// 영상 전환은 인스펙터 영상 탭에, 크로스페이드는 오디오 탭에 둔다(#90). 줄만 내보내고, 섹션은 인스펙터가 둔다.
struct TransitionInspectorView: View {
    enum Part {
        /// 영상 전환(디졸브·와이프).
        case video
        /// 오디오 크로스페이드.
        case audio
    }

    let part: Part
    let clip: Clip
    /// 앞 클립과 맞닿지 않았으면 0이다.
    let maximumDuration: CMTime
    let setTransition: (ClipTransition?) -> Void
    let setAudioCrossfade: (CMTime?) -> Void
    @State private var editingTransitionSeconds: Double?
    @State private var editingCrossfadeSeconds: Double?

    var body: some View {
        if maximumDuration < ClipTransition.minimumDuration {
            note("같은 트랙에서 바로 앞 클립과 틈 없이 맞닿은 클립에만 둘 수 있습니다.")
        } else {
            switch part {
            case .video: videoRows
            case .audio: audioRows
            }
        }
    }

    private var transition: ClipTransition? {
        clip.transitionIn.map { ClipTransition(kind: $0.kind, duration: CMTimeMinimum($0.duration, maximumDuration)) }
    }

    @ViewBuilder
    private var videoRows: some View {
        Picker("종류", selection: Binding(
            get: { transition?.kind },
            set: { kind in
                setTransition(kind.map { ClipTransition(kind: $0, duration: transition?.duration ?? defaultDuration) })
            }
        )) {
            Text("없음").tag(TransitionKind?.none)
            Text("디졸브").tag(TransitionKind?.some(.dissolve))
            Text("와이프").tag(TransitionKind?.some(.wipe))
        }
        .pickerStyle(.segmented)
        if let transition {
            durationSlider(seconds: transition.duration.seconds, editing: $editingTransitionSeconds) { seconds in
                setTransition(ClipTransition(kind: transition.kind, duration: time(seconds)))
            }
        }
        note("앞 클립에서 넘어올 때의 전환입니다. 컷 지점을 가운데 두고 앞뒤로 절반씩 걸칩니다. 원본 앞뒤 여분이 모자라면 끝·첫 프레임을 멈춰 채웁니다.")
    }

    @ViewBuilder
    private var audioRows: some View {
        Toggle("크로스페이드", isOn: Binding(
            get: { clip.audioCrossfadeIn != nil },
            set: { setAudioCrossfade($0 ? defaultDuration : nil) }
        ))
        if let crossfade = clip.audioCrossfadeIn.map({ CMTimeMinimum($0, maximumDuration) }) {
            durationSlider(seconds: crossfade.seconds, editing: $editingCrossfadeSeconds) { seconds in
                setAudioCrossfade(time(seconds))
            }
        }
        note("앞 클립 소리를 줄이며 이 클립 소리를 키웁니다. 영상 전환(영상 탭)과 따로 켜고 끕니다.")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var defaultDuration: CMTime {
        CMTimeMinimum(ClipTransition.defaultDuration, maximumDuration)
    }

    /// 손을 뗄 때만 반영해 실행 취소가 잘게 쌓이지 않게 한다.
    private func durationSlider(seconds: Double, editing: Binding<Double?>, commit: @escaping (Double) -> Void) -> some View {
        let shown = editing.wrappedValue ?? seconds
        return LabeledContent {
            Slider(
                value: Binding(get: { shown }, set: { editing.wrappedValue = $0 }),
                in: ClipTransition.minimumDuration.seconds ... maximumDuration.seconds,
                onEditingChanged: { isEditing in
                    if !isEditing, let value = editing.wrappedValue {
                        commit(value)
                        editing.wrappedValue = nil
                    }
                }
            )
            Text(shown, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        } label: {
            Text("길이(초)")
        }
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: standardTimescale)
    }
}
