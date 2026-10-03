import CoreMedia
import SwiftUI

/// 편집 컨트롤은 클립 자르기(#2)에서 활성화한다.
struct TrimInspectorView: View {
    let clip: Clip

    var body: some View {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2))
        let startText = Duration.seconds(clip.sourceRange.start.seconds).formatted(format)
        let endText = Duration.seconds(clip.sourceRange.end.seconds).formatted(format)
        let timelineStartText = Duration.seconds(clip.timelineStart.seconds).formatted(format)

        Form {
            Section {
                TextField("시작 지점", text: .constant(startText))
                TextField("종료 지점", text: .constant(endText))
                TextField("타임라인 위치", text: .constant(timelineStartText))
                Stepper("재생 속도 1.0×", value: .constant(1.0), in: 0.25 ... 4, step: 0.25)
            } footer: {
                Text("트림 편집은 준비 중입니다.")
            }
        }
        .formStyle(.grouped)
        .disabled(true)
    }
}
