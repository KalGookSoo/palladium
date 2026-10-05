import CoreMedia
import SwiftUI

/// 원본에서 쓸 구간(시작·끝 지점)을 초 단위로 입력한다. 타임라인에서 클립 끝을 끄는 것과 같은 리플 트림이다(뒤 클립이 따라온다).
/// 재생 속도·역재생은 #58에서 다룬다.
struct TrimInspectorView: View {
    let clip: Clip
    /// 원본 길이. 이미지는 길이 제한이 없어 `nil`.
    let sourceDuration: CMTime?
    let setSource: (CMTime, CMTime) -> Void

    var body: some View {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2))
        let start = Binding<Double>(
            get: { clip.sourceRange.start.seconds },
            set: { setSource(seconds($0), clip.sourceRange.end) }
        )
        let end = Binding<Double>(
            get: { clip.sourceRange.end.seconds },
            set: { setSource(clip.sourceRange.start, seconds($0)) }
        )

        Form {
            Section {
                // 이미지는 원본 시작이 항상 0이라 길이(끝 지점)만 바꾼다.
                if sourceDuration != nil {
                    TextField("시작 지점(초)", value: start, format: .number.precision(.fractionLength(2)))
                }
                TextField(sourceDuration == nil ? "길이(초)" : "종료 지점(초)", value: end, format: .number.precision(.fractionLength(2)))
                LabeledContent("길이", value: Duration.seconds(clip.sourceRange.duration.seconds).formatted(format))
                LabeledContent("타임라인 위치", value: Duration.seconds(clip.timelineStart.seconds).formatted(format))
                if let sourceDuration {
                    LabeledContent("원본 길이", value: Duration.seconds(sourceDuration.seconds).formatted(format))
                }
            } footer: {
                Text("값을 입력하거나 타임라인에서 클립 끝을 끌어 트림합니다. 뒤 클립이 따라오고, 끌 때 ⌥를 누르면 정밀하게 조정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
