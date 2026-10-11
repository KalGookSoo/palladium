import SwiftUI

/// 클립 소리 이펙트(#74): 게인(원본보다 크게도), 저음 웅웅거림 깎기, 노이즈 게이트, 저·중·고 이퀄라이저, 잔향.
/// 슬라이더는 손을 뗄 때 반영하고, 미리보기와 내보내기에 같이 들어간다. 인스펙터 오디오 탭의 섹션 줄만 내보낸다.
struct AudioEffectsInspectorView: View {
    let effects: AudioEffects
    let setEffects: (AudioEffects) -> Void

    var body: some View {
        CommitSlider(title: "게인", value: effects.gain, range: AudioEffects.gainRange, text: decibels) { value in change { $0.gain = value.rounded() } }
            .help("소리를 원본보다 키우거나 줄입니다(dB). 음량(0~100%)과 곱해집니다. 너무 키우면 소리가 찌그러집니다")
        Toggle("저음 웅웅거림 깎기(80Hz)", isOn: Binding(get: { effects.cutsLowRumble }, set: { value in change { $0.cutsLowRumble = value } }))
            .help("바람 소리·책상 울림처럼 낮게 웅웅거리는 소리를 줄입니다")
        CommitSlider(title: "노이즈 게이트", value: effects.noiseGate, range: 0 ... 1, text: percent) { value in change { $0.noiseGate = value } }
            .help("말이 없을 때 들리는 작은 잡음을 줄입니다. 올릴수록 더 큰 소리까지 잡음으로 봅니다(말끝이 잘리면 낮추세요)")
        CommitSlider(title: "저음", value: effects.lowGain, range: AudioEffects.gainRange, text: decibels) { value in change { $0.lowGain = value.rounded() } }
        CommitSlider(title: "중음", value: effects.midGain, range: AudioEffects.gainRange, text: decibels) { value in change { $0.midGain = value.rounded() } }
        CommitSlider(title: "고음", value: effects.highGain, range: AudioEffects.gainRange, text: decibels) { value in change { $0.highGain = value.rounded() } }
        CommitSlider(title: "잔향", value: effects.reverb, range: 0 ... 1, text: percent) { value in change { $0.reverb = value } }
            .help("작은 방에서 울리는 듯한 잔향을 섞습니다")
        Button("초기화") { setEffects(AudioEffects()) }
            .disabled(effects.isDefault)
    }

    private func change(_ edit: (inout AudioEffects) -> Void) {
        var changed = effects
        edit(&changed)
        setEffects(changed)
    }

    private func decibels(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)dB" : "\(rounded)dB"
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}
