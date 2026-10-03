import SwiftUI

/// 도메인에 트랜스폼 값이 생기기 전까지(#9) 고정값으로 완성 모습만 보여주는 목업이다.
struct TransformInspectorView: View {
    var body: some View {
        Form {
            Section {
                TextField("위치 X", text: .constant("0"))
                TextField("위치 Y", text: .constant("0"))
                Slider(value: .constant(100), in: 10 ... 400) { Text("크기 (%)") }
                Slider(value: .constant(0), in: -180 ... 180) { Text("회전 (°)") }
                Slider(value: .constant(100), in: 0 ... 100) { Text("불투명도 (%)") }
            } footer: {
                Text("트랜스폼 편집은 준비 중입니다.")
            }
        }
        .formStyle(.grouped)
        .disabled(true)
    }
}
