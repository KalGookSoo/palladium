import SwiftUI

/// 클립의 위치·크기·불투명도. 미리보기에서 클립 테두리를 끌어도 같은 값이 바뀐다(#9).
struct TransformInspectorView: View {
    let transform: ClipTransform
    let setTransform: (ClipTransform) -> Void

    var body: some View {
        Form {
            Section {
                percentSlider("위치 X", value: \.centerX, range: -0.5 ... 1.5)
                percentSlider("위치 Y", value: \.centerY, range: -0.5 ... 1.5)
                percentSlider("크기", value: \.scale, range: ClipTransform.scaleRange)
                percentSlider("불투명도", value: \.opacity, range: 0 ... 1)
                Button("초기화") { setTransform(ClipTransform()) }
                    .disabled(transform == ClipTransform())
            } footer: {
                Text("미리보기에서 클립을 고른 뒤 테두리 안을 끌어 옮기고, 오른쪽 아래 손잡이를 끌어 크기를 바꿀 수도 있습니다. 위쪽 영상 트랙의 클립은 아래 트랙 위에 겹쳐 보입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 손을 뗄 때만 값을 반영해, 끄는 동안 실행 취소가 잘게 쌓이지 않게 한다.
    private func percentSlider(_ title: String, value keyPath: WritableKeyPath<ClipTransform, Double>, range: ClosedRange<Double>) -> some View {
        TransformSlider(title: title, value: transform[keyPath: keyPath], range: range) { newValue in
            var updated = transform
            updated[keyPath: keyPath] = newValue
            setTransform(updated)
        }
    }
}

private struct TransformSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
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
            Text(shown, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        } label: {
            Text(title)
        }
    }
}
