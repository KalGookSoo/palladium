import SwiftUI

/// 도메인에 자막 값이 생기기 전까지(#4) 고정값으로 완성 모습만 보여주는 목업이다.
struct SubtitleInspectorView: View {
    var body: some View {
        Form {
            Section {
                TextField("자막 텍스트", text: .constant(""), prompt: Text("자막을 입력하세요"))
                Stepper("글꼴 크기 24pt", value: .constant(24), in: 8 ... 96)
                Picker("위치", selection: .constant("아래")) {
                    Text("위").tag("위")
                    Text("가운데").tag("가운데")
                    Text("아래").tag("아래")
                }
            } footer: {
                Text("자막 편집은 준비 중입니다.")
            }
        }
        .formStyle(.grouped)
        .disabled(true)
    }
}
