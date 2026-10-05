import CoreMedia
import SwiftUI

/// 바로 앞 클립에서 이 클립으로 넘어가는 영상 전환과 오디오 크로스페이드(#8). 둘은 따로 정한다.
struct TransitionInspectorView: View {
    let clip: Clip
    /// 소리만 있는 클립은 영상 전환을, 이미지 클립은 크로스페이드를 보여주지 않는다.
    let hasPicture: Bool
    let hasSound: Bool
    /// 앞 클립과 맞닿지 않았으면 0이다.
    let maximumDuration: CMTime
    let setTransition: (ClipTransition?) -> Void
    let setAudioCrossfade: (CMTime?) -> Void
    @State private var editingTransitionSeconds: Double?
    @State private var editingCrossfadeSeconds: Double?

    var body: some View {
        if maximumDuration < ClipTransition.minimumDuration {
            ContentUnavailableView(
                "앞에 붙은 클립 없음",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("같은 트랙에서 바로 앞 클립과 틈 없이 맞닿은 클립에만 전환을 둘 수 있습니다")
            )
        } else {
            Form {
                if hasPicture {
                    videoSection
                }
                if hasSound {
                    audioSection
                }
            }
            .formStyle(.grouped)
        }
    }

    private var transition: ClipTransition? {
        clip.transitionIn.map { ClipTransition(kind: $0.kind, duration: CMTimeMinimum($0.duration, maximumDuration)) }
    }

    private var videoSection: some View {
        Section {
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
        } header: {
            Text("영상 전환")
        } footer: {
            Text("컷 지점을 가운데 두고 앞뒤로 절반씩 걸칩니다. 원본 앞뒤 여분이 모자라면 끝·첫 프레임을 멈춰 채웁니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var audioSection: some View {
        Section {
            Toggle("크로스페이드", isOn: Binding(
                get: { clip.audioCrossfadeIn != nil },
                set: { setAudioCrossfade($0 ? defaultDuration : nil) }
            ))
            if let crossfade = clip.audioCrossfadeIn.map({ CMTimeMinimum($0, maximumDuration) }) {
                durationSlider(seconds: crossfade.seconds, editing: $editingCrossfadeSeconds) { seconds in
                    setAudioCrossfade(time(seconds))
                }
            }
        } header: {
            Text("오디오")
        } footer: {
            Text("앞 클립 소리를 줄이며 이 클립 소리를 키웁니다. 영상 전환과 따로 켜고 끕니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
