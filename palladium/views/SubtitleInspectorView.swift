import CoreMedia
import SwiftUI

/// 자막 트랙에서 고른 자막의 글자·모양·시간(#4).
struct SubtitleInspectorView: View {
    let subtitle: Subtitle
    let update: (String, SubtitleStyle) -> Void
    let setRange: (CMTime, CMTime) -> Void
    let delete: () -> Void
    /// 입력 중인 글자. 입력란을 떠나거나 다른 자막을 고르면 반영한다(글자마다 실행 취소가 쌓이지 않게).
    @State private var editingText: String?
    @State private var editingFontSize: Double?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        let style = subtitle.style
        let start = Binding<Double>(
            get: { subtitle.range.start.seconds },
            set: { setRange(seconds($0), subtitle.range.end) }
        )
        let end = Binding<Double>(
            get: { subtitle.range.end.seconds },
            set: { setRange(subtitle.range.start, seconds($0)) }
        )

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                Text("자막")
                    .font(.headline)
                Text("\(SubtitleFile.timecode(subtitle.range.start)) → \(SubtitleFile.timecode(subtitle.range.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding()

            Form {
                Section("글자") {
                    TextField("자막", text: Binding(get: { editingText ?? subtitle.text }, set: { editingText = $0 }), axis: .vertical)
                        .lineLimit(2 ... 5)
                        .labelsHidden()
                        .focused($isTextFocused)
                        .onSubmit(commitText)
                }
                Section("모양") {
                    LabeledContent {
                        Slider(
                            value: Binding(get: { editingFontSize ?? style.fontSize }, set: { editingFontSize = $0 }),
                            in: SubtitleStyle.fontSizeRange,
                            onEditingChanged: { isEditing in
                                if !isEditing, let editingFontSize {
                                    var changed = style
                                    changed.fontSize = editingFontSize.rounded()
                                    update(subtitle.text, changed)
                                    self.editingFontSize = nil
                                }
                            }
                        )
                        Text("\(Int(editingFontSize ?? style.fontSize))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    } label: {
                        Text("크기")
                    }
                    Picker("위치", selection: styleBinding(\.position)) {
                        Text("위").tag(SubtitlePosition.top)
                        Text("가운데").tag(SubtitlePosition.middle)
                        Text("아래").tag(SubtitlePosition.bottom)
                    }
                    .pickerStyle(.segmented)
                    Picker("색", selection: styleBinding(\.color)) {
                        Text("흰색").tag(SubtitleColor.white)
                        Text("노란색").tag(SubtitleColor.yellow)
                    }
                    .pickerStyle(.segmented)
                    Toggle("배경 상자", isOn: styleBinding(\.hasBackground))
                }
                Section {
                    TextField("시작(초)", value: start, format: .number.precision(.fractionLength(2)))
                    TextField("끝(초)", value: end, format: .number.precision(.fractionLength(2)))
                } header: {
                    Text("시간")
                } footer: {
                    Text("자막은 결과물 시간에 붙어 클립을 옮겨도 따라가지 않습니다. 타임라인 자막 트랙에서 끌어 옮기거나 양 끝을 끌어 바꿀 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("자막 삭제", role: .destructive, action: delete)
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: isTextFocused) {
            if !isTextFocused {
                commitText()
            }
        }
        // 상위가 자막마다 `.id`를 달아, 다른 자막을 고르면 이 화면이 사라지며 입력하던 글자를 원래 자막에 반영한다.
        .onDisappear(perform: commitText)
    }

    private func commitText() {
        guard let editingText else { return }
        self.editingText = nil
        if editingText != subtitle.text {
            update(editingText, subtitle.style)
        }
    }

    private func styleBinding<Value>(_ keyPath: WritableKeyPath<SubtitleStyle, Value>) -> Binding<Value> {
        Binding(
            get: { subtitle.style[keyPath: keyPath] },
            set: { value in
                var changed = subtitle.style
                changed[keyPath: keyPath] = value
                update(editingText ?? subtitle.text, changed)
                editingText = nil
            }
        )
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
