import CoreMedia
import SwiftUI

/// 마스크 레인에서 고른 마스크의 효과·모양·영역·시간(#59). 영역은 미리보기에서 끌어서도 바꾼다.
struct MaskInspectorView: View {
    let mask: Mask
    let update: (Mask) -> Void
    let setRange: (CMTime, CMTime) -> Void
    let delete: () -> Void
    @State private var editingStrength: Double?

    var body: some View {
        let start = Binding<Double>(
            get: { mask.range.start.seconds },
            set: { setRange(seconds($0), mask.range.end) }
        )
        let end = Binding<Double>(
            get: { mask.range.end.seconds },
            set: { setRange(mask.range.start, seconds($0)) }
        )
        let shownStrength = editingStrength ?? mask.strength

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                Text("마스크")
                    .font(.headline)
                Text("\(SubtitleFile.timecode(mask.range.start)) → \(SubtitleFile.timecode(mask.range.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding()

            Form {
                Section("효과") {
                    Picker("효과", selection: binding(\.effect)) {
                        ForEach(MaskEffect.allCases, id: \.self) { effect in
                            Text(effect.title).tag(effect)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("모양", selection: binding(\.shape)) {
                        Text("사각형").tag(MaskShape.rectangle)
                        Text("타원").tag(MaskShape.ellipse)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent {
                        // 손을 뗄 때만 반영해 실행 취소가 잘게 쌓이지 않게 한다.
                        Slider(
                            value: Binding(get: { shownStrength }, set: { editingStrength = $0 }),
                            in: 0 ... 1,
                            onEditingChanged: { isEditing in
                                if !isEditing, let editingStrength {
                                    var changed = mask
                                    changed.strength = editingStrength
                                    update(changed)
                                    self.editingStrength = nil
                                }
                            }
                        )
                        Text(shownStrength, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    } label: {
                        Text("세기")
                    }
                }
                Section {
                    TextField("가운데 X(%)", value: percentBinding(\.area.centerX), format: .number.precision(.fractionLength(0)))
                    TextField("가운데 Y(%)", value: percentBinding(\.area.centerY), format: .number.precision(.fractionLength(0)))
                    TextField("너비(%)", value: percentBinding(\.area.width), format: .number.precision(.fractionLength(0)))
                    TextField("높이(%)", value: percentBinding(\.area.height), format: .number.precision(.fractionLength(0)))
                } header: {
                    Text("영역")
                } footer: {
                    Text("화면 크기에 대한 비율입니다. 미리보기에서 테두리 안을 끌어 옮기고 오른쪽 아래 손잡이로 크기를 바꿉니다. 영역은 화면에 고정되어 피사체를 따라가지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("시간") {
                    TextField("시작(초)", value: start, format: .number.precision(.fractionLength(2)))
                    TextField("끝(초)", value: end, format: .number.precision(.fractionLength(2)))
                }
                Section {
                    Button("마스크 삭제", role: .destructive, action: delete)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Mask, Value>) -> Binding<Value> {
        Binding(
            get: { mask[keyPath: keyPath] },
            set: { value in
                var changed = mask
                changed[keyPath: keyPath] = value
                update(changed)
            }
        )
    }

    /// 0~1 비율을 0~100으로 입력받는다.
    private func percentBinding(_ keyPath: WritableKeyPath<Mask, Double>) -> Binding<Double> {
        Binding(
            get: { mask[keyPath: keyPath] * 100 },
            set: { value in
                var changed = mask
                changed[keyPath: keyPath] = value / 100
                update(changed)
            }
        )
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
