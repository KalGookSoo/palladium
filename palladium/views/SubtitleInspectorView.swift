import AppKit
import CoreMedia
import SwiftUI

/// 자막 트랙에서 고른 자막의 글자·모양·시간(#4).
/// 위치는 미리보기에서 끌거나 자막을 고른 채 방향키로도 옮긴다. 슬라이더는 손을 뗄 때 반영한다(#82).
struct SubtitleInspectorView: View {
    let subtitle: Subtitle
    /// 합성 화면 크기. 위치 슬라이더가 실제로 보이는 자리(가장자리 여백에 맞춘 상자)에서 시작하게 한다.
    var renderSize = SequenceComposer.renderSize(for: .landscape16x9)
    let update: (String, SubtitleStyle) -> Void
    /// 화면 비율 좌표(0~1)로 자막 위치를 바꾼다.
    var setPosition: (Double, Double) -> Void = { _, _ in }
    let setRange: (CMTime, CMTime) -> Void
    let delete: () -> Void
    /// 입력 중인 글자. 입력란을 떠나거나 다른 자막을 고르면 반영한다(글자마다 실행 취소가 쌓이지 않게).
    @State private var editingText: String?
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
                    CommitSlider(title: "크기", value: style.fontSize, range: SubtitleStyle.fontSizeRange, text: { "\(Int($0))" }) { size in
                        changeStyle { $0.fontSize = size.rounded() }
                    }
                    fontPickers(style: style)
                }
                Section("위치") {
                    // 위·가운데·아래는 그 자리로 한 번에 옮기는 빠른 버튼이다.
                    HStack {
                        ForEach(SubtitlePosition.allCases, id: \.self) { position in
                            Button(position.title) { changeStyle { $0.move(to: position) } }
                                .buttonStyle(.bordered)
                                .tint(style.preset == position ? .accentColor : nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    let shown = shownCenter
                    positionRow("가로", value: shown.x) { setPosition($0, shown.y) }
                    positionRow("세로", value: shown.y) { setPosition(shown.x, $0) }
                }
                Section("색") {
                    LabeledContent("글자색") { PopoverColorWell(color: colorBinding(\.textColor)) }
                    CommitSlider(title: "글자 불투명도", value: style.textOpacity, range: 0 ... 1, text: percent) { opacity in
                        changeStyle { $0.textOpacity = opacity }
                    }
                    LabeledContent("배경색") { PopoverColorWell(color: colorBinding(\.backgroundColor)) }
                    CommitSlider(title: "배경 불투명도", value: style.backgroundOpacity, range: 0 ... 1, text: percent) { opacity in
                        changeStyle { $0.backgroundOpacity = opacity }
                    }
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

    private func changeStyle(_ change: (inout SubtitleStyle) -> Void) {
        var changed = subtitle.style
        change(&changed)
        update(editingText ?? subtitle.text, changed)
        editingText = nil
    }

    /// 실제로 보이는 상자 가운데(화면 비율). 글자가 비어 있으면 저장된 위치.
    private var shownCenter: CGPoint {
        guard let frame = SubtitleRenderer.frame(for: subtitle, renderSize: renderSize) else {
            return CGPoint(x: subtitle.style.centerX, y: subtitle.style.centerY)
        }
        return CGPoint(x: frame.midX / renderSize.width, y: frame.midY / renderSize.height)
    }

    private func positionRow(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            CommitSlider(title: title, value: value, range: 0 ... 1, text: percent, commit: set)
            TextField(title, value: Binding(get: { (value * 100).rounded() }, set: { set($0 / 100) }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    /// 설치된 글꼴 가족과 그 가족의 굵기. 이 Mac에 없는 글꼴이면 알리고 기본 글꼴로 그린다.
    @ViewBuilder
    private func fontPickers(style: SubtitleStyle) -> some View {
        let isAvailable = SubtitleRenderer.isFontAvailable(style.fontName)
        let family = NSFont(name: isAvailable ? style.fontName : SubtitleStyle.defaultFontName, size: 12)?.familyName ?? ""
        let members = FontCatalog.members(of: family)
        Picker("글꼴", selection: Binding(get: { family }, set: { newFamily in
            let currentWeight = members.first { $0.postScriptName == style.fontName }?.weight ?? 5
            if let member = FontCatalog.closestMember(of: newFamily, toWeight: currentWeight) {
                changeStyle { $0.fontName = member.postScriptName }
            }
        })) {
            ForEach(FontCatalog.families, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        Picker("굵기", selection: Binding(get: { isAvailable ? style.fontName : SubtitleStyle.defaultFontName }, set: { name in
            changeStyle { $0.fontName = name }
        })) {
            ForEach(members, id: \.postScriptName) { member in
                Text(member.faceName).tag(member.postScriptName)
            }
        }
        if !isAvailable {
            Label("글꼴 없음: \(style.fontName) — 기본 글꼴로 그립니다", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<SubtitleStyle, SubtitleRGB>) -> Binding<Color> {
        Binding(
            get: {
                let color = subtitle.style[keyPath: keyPath]
                return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let changed = SubtitleRGB(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                guard changed != subtitle.style[keyPath: keyPath] else { return }
                changeStyle { $0[keyPath: keyPath] = changed }
            }
        )
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}

private extension SubtitlePosition {
    var title: String {
        switch self {
        case .top: "위"
        case .middle: "가운데"
        case .bottom: "아래"
        }
    }
}

/// 끄는 동안은 숫자만 바꾸고 손을 뗄 때 반영한다(실행 취소가 잘게 쌓이지 않게).
private struct CommitSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let text: (Double) -> String
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
            Text(text(shown))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        } label: {
            Text(title)
        }
    }
}

/// 이 Mac에 설치된 글꼴 가족과 굵기(기기 안의 글꼴만 쓴다).
private enum FontCatalog {
    struct Member {
        let postScriptName: String
        let faceName: String
        let weight: Int
    }

    static let families = NSFontManager.shared.availableFontFamilies.sorted()

    static func members(of family: String) -> [Member] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count >= 3, let name = member[0] as? String, let face = member[1] as? String, let weight = member[2] as? Int else { return nil }
            return Member(postScriptName: name, faceName: face, weight: weight)
        }
    }

    /// 가족을 바꿀 때 지금 굵기와 가장 가까운 굵기를 고른다.
    static func closestMember(of family: String, toWeight weight: Int) -> Member? {
        members(of: family).min { abs($0.weight - weight) < abs($1.weight - weight) }
    }
}
