import SwiftUI

/// 도메인에 이펙트 값이 생기기 전까지(#9) 고정값으로 완성 모습만 보여주는 목업이다.
struct EffectInspectorView: View {
    var body: some View {
        Form {
            Section {
                Picker("필터", selection: .constant("없음")) {
                    Text("없음").tag("없음")
                }
                Slider(value: .constant(0), in: -1 ... 1) { Text("밝기") }
                Slider(value: .constant(1), in: 0 ... 2) { Text("대비") }
                Slider(value: .constant(1), in: 0 ... 2) { Text("채도") }
            } footer: {
                Text("이펙트 편집은 준비 중입니다.")
            }
        }
        .formStyle(.grouped)
        .disabled(true)
    }
}
