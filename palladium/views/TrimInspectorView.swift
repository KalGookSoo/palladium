import CoreMedia
import SwiftUI

/// 원본에는 아직 트림 정보가 없으므로 전체 구간을 보여준다. 편집은 클립 자르기(#2)에서 활성화한다.
struct TrimInspectorView: View {
    let asset: MediaAsset

    var body: some View {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2))
        let startText = Duration.seconds(0).formatted(format)
        let endText = Duration.seconds(asset.duration.seconds).formatted(format)

        Form {
            Section {
                TextField("시작 지점", text: .constant(startText))
                TextField("종료 지점", text: .constant(endText))
                Stepper("재생 속도 1.0×", value: .constant(1.0), in: 0.25 ... 4, step: 0.25)
            } footer: {
                Text("트림 편집은 준비 중입니다.")
            }
        }
        .formStyle(.grouped)
        .disabled(true)
    }
}
