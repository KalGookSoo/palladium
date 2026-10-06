import SwiftUI

/// 영상·이미지 클립의 밝기·대비·채도(#61). 손을 뗄 때 한 번의 편집으로 반영하고 그때 미리보기가 바뀐다.
/// 여러 클립을 골랐으면 고른 영상·이미지 클립 모두에 같은 값이 들어간다.
struct EffectInspectorView: View {
    let adjustment: ColorAdjustment
    /// 여러 클립을 골랐을 때 아래에 알린다.
    var appliesToMultipleClips = false
    let setAdjustment: (ColorAdjustment) -> Void

    var body: some View {
        Form {
            Section {
                slider("밝기", \.brightness, range: ColorAdjustment.brightnessRange, format: .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
                slider("대비", \.contrast, range: ColorAdjustment.contrastRange, format: .percent.precision(.fractionLength(0)))
                slider("채도", \.saturation, range: ColorAdjustment.saturationRange, format: .percent.precision(.fractionLength(0)))
                Button("초기화") { setAdjustment(ColorAdjustment()) }
                    .disabled(adjustment.isDefault)
            } header: {
                Text("색보정")
            } footer: {
                Text(appliesToMultipleClips
                    ? "고른 영상·이미지 클립 모두에 같은 값이 들어갑니다. 값은 첫 클립 기준으로 보입니다."
                    : "채도를 0으로 내리면 흑백이 됩니다. 손을 떼면 미리보기에 반영됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func slider<Format: FormatStyle>(
        _ title: String,
        _ keyPath: WritableKeyPath<ColorAdjustment, Double>,
        range: ClosedRange<Double>,
        format: Format
    ) -> some View where Format.FormatInput == Double, Format.FormatOutput == String {
        AdjustmentSlider(
            title: title,
            value: adjustment[keyPath: keyPath],
            defaultValue: ColorAdjustment()[keyPath: keyPath],
            range: range,
            format: format
        ) { newValue in
            var updated = adjustment
            updated[keyPath: keyPath] = newValue
            setAdjustment(updated)
        }
    }
}

/// 끄는 동안은 숫자만 바꾸고 손을 뗄 때 반영한다(실행 취소가 잘게 쌓이지 않게). ↺는 그 값만 기본값으로 돌린다.
private struct AdjustmentSlider<Format: FormatStyle>: View where Format.FormatInput == Double, Format.FormatOutput == String {
    let title: String
    let value: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    let format: Format
    let commit: (Double) -> Void
    @State private var editingValue: Double?

    var body: some View {
        let shown = editingValue ?? value
        LabeledContent {
            Slider(
                value: Binding(get: { shown }, set: { editingValue = $0 }),
                in: range,
                onEditingChanged: { isEditing in
                    if !isEditing, let editingValue {
                        commit(editingValue)
                        self.editingValue = nil
                    }
                }
            )
            Text(shown, format: format)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Button {
                commit(defaultValue)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(value == defaultValue)
            .help("\(title) 되돌리기")
        } label: {
            Text(title)
        }
    }
}

#Preview {
    EffectInspectorView(adjustment: ColorAdjustment(brightness: 0.1, contrast: 1.2, saturation: 0)) { _ in }
        .frame(width: 300, height: 320)
}
