import AppKit
import SwiftUI

/// 타이틀 클립(#76)의 글자·글꼴·크기·색·외곽선·그림자·배경. 인스펙터 영상 탭의 섹션 줄만 내보낸다.
/// 위치·크기·회전·불투명도는 트랜스폼 섹션과 미리보기 테두리에서, 나타나고 사라지는 연출은 키프레임(페이드 인·아웃)으로 한다.
struct TitleInspectorView: View {
    let title: TitleText
    let setTitle: (TitleText) -> Void
    /// 입력 중인 글자. 입력란을 떠나면 반영한다(글자마다 실행 취소가 쌓이지 않게).
    @State private var editingText: String?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        TextField("글자", text: Binding(get: { editingText ?? title.text }, set: { editingText = $0 }), axis: .vertical)
            .lineLimit(1 ... 4)
            .labelsHidden()
            .focused($isTextFocused)
            .onSubmit(commitText)
            .onChange(of: isTextFocused) {
                if !isTextFocused {
                    commitText()
                }
            }
            .onDisappear(perform: commitText)
            .help("여러 줄은 ⌥Return으로 바꿉니다. 입력란을 떠나면 반영됩니다")
        CommitSlider(title: "크기", value: title.fontSize, range: TitleText.fontSizeRange, text: { "\(Int($0))" }) { size in
            change { $0.fontSize = size.rounded() }
        }
        fontPickers
        LabeledContent("글자색") { PopoverColorWell(color: colorBinding(\.textColor)) }
        CommitSlider(title: "외곽선", value: title.outlineWidth, range: TitleText.outlineWidthRange, text: { "\(Int($0))" }) { width in
            change { $0.outlineWidth = width.rounded() }
        }
        LabeledContent("외곽선 색") { PopoverColorWell(color: colorBinding(\.outlineColor)) }
            .disabled(title.outlineWidth == 0)
        Toggle("그림자", isOn: Binding(get: { title.hasShadow }, set: { shadow in change { $0.hasShadow = shadow } }))
        LabeledContent("배경색") { PopoverColorWell(color: colorBinding(\.backgroundColor)) }
        CommitSlider(title: "배경 불투명도", value: title.backgroundOpacity, range: 0 ... 1, text: { $0.formatted(.percent.precision(.fractionLength(0))) }) { opacity in
            change { $0.backgroundOpacity = opacity }
        }
    }

    private func commitText() {
        guard let editingText else { return }
        self.editingText = nil
        if editingText != title.text {
            change { $0.text = editingText }
        }
    }

    private func change(_ edit: (inout TitleText) -> Void) {
        var changed = title
        if let editingText {
            changed.text = editingText
            self.editingText = nil
        }
        edit(&changed)
        setTitle(changed)
    }

    /// 설치된 글꼴 가족과 굵기(자막과 같은 목록).
    @ViewBuilder
    private var fontPickers: some View {
        let isAvailable = SubtitleRenderer.isFontAvailable(title.fontName)
        let family = NSFont(name: isAvailable ? title.fontName : SubtitleStyle.defaultFontName, size: 12)?.familyName ?? ""
        let members = FontCatalog.members(of: family)
        Picker("글꼴", selection: Binding(get: { family }, set: { newFamily in
            let currentWeight = members.first { $0.postScriptName == title.fontName }?.weight ?? 5
            if let member = FontCatalog.closestMember(of: newFamily, toWeight: currentWeight) {
                change { $0.fontName = member.postScriptName }
            }
        })) {
            ForEach(FontCatalog.families, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        Picker("굵기", selection: Binding(get: { isAvailable ? title.fontName : SubtitleStyle.defaultFontName }, set: { name in
            change { $0.fontName = name }
        })) {
            ForEach(members, id: \.postScriptName) { member in
                Text(member.faceName).tag(member.postScriptName)
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<TitleText, SubtitleRGB>) -> Binding<Color> {
        Binding(
            get: {
                let color = title[keyPath: keyPath]
                return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let changed = SubtitleRGB(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                guard changed != title[keyPath: keyPath] else { return }
                change { $0[keyPath: keyPath] = changed }
            }
        )
    }
}
