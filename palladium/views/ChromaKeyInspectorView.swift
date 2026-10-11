import AppKit
import SwiftUI

/// 크로마키(#70): 그린스크린·블루스크린 배경을 빼 아래 트랙과 합성한다. 위 영상 트랙의 클립에 켜면 아래 트랙이 비친다.
/// 키 색은 초록·파랑 버튼, 색 상자, 또는 스포이트(화면에서 색 고르기)로 정한다. 슬라이더는 손을 뗄 때 반영한다.
/// 여러 클립을 골랐으면 고른 영상·이미지 클립 모두에 같은 설정이 들어간다. 줄만 내보내고 섹션은 인스펙터가 둔다.
struct ChromaKeyInspectorView: View {
    let chromaKey: ChromaKey?
    let setChromaKey: (ChromaKey?) -> Void

    var body: some View {
        Toggle("크로마키", isOn: Binding(get: { chromaKey != nil }, set: { setChromaKey($0 ? ChromaKey() : nil) }))
            .help("배경색(초록·파랑 등)을 투명하게 빼 아래 트랙이 비치게 합니다")
        if let chromaKey {
            LabeledContent("키 색") {
                HStack(spacing: 6) {
                    Button("초록") { change { $0.keyColor = ChromaKey.green } }
                    Button("파랑") { change { $0.keyColor = ChromaKey.blue } }
                    PopoverColorWell(color: colorBinding(chromaKey))
                    Button {
                        NSColorSampler().show { color in
                            guard let rgb = color?.usingColorSpace(.sRGB) else { return }
                            change { $0.keyColor = SubtitleRGB(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent) }
                        }
                    } label: {
                        Label("스포이트", systemImage: "eyedropper")
                    }
                    .labelStyle(.iconOnly)
                    .help("스포이트 — 미리보기에서 뺄 배경색을 눌러 고릅니다")
                }
                .controlSize(.small)
            }
            CommitSlider(title: "허용 범위", value: chromaKey.tolerance, range: 0 ... 1, text: percent) { value in change { $0.tolerance = value } }
            CommitSlider(title: "부드러움", value: chromaKey.softness, range: 0 ... 1, text: percent) { value in change { $0.softness = value } }
            CommitSlider(title: "색 번짐 제거", value: chromaKey.spillSuppression, range: 0 ... 1, text: percent) { value in change { $0.spillSuppression = value } }
            Text("배경이 남으면 허용 범위를 넓히고, 인물 가장자리가 깨지면 부드러움을 올립니다. 가장자리에 남은 초록 기운은 색 번짐 제거로 뺍니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func change(_ edit: (inout ChromaKey) -> Void) {
        var changed = chromaKey ?? ChromaKey()
        edit(&changed)
        setChromaKey(changed)
    }

    private func colorBinding(_ key: ChromaKey) -> Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: key.keyColor.red, green: key.keyColor.green, blue: key.keyColor.blue) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let changed = SubtitleRGB(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                guard changed != key.keyColor else { return }
                change { $0.keyColor = changed }
            }
        )
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}
