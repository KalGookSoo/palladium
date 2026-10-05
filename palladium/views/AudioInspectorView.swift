import SwiftUI

/// 클립 소리의 크기와 음소거(#44). 트랙 전체는 트랙 이름 옆 스피커 버튼과 트랙 이름 우클릭 메뉴로 바꾼다.
struct AudioInspectorView: View {
    let clip: Clip
    let setAudio: (Double, Bool) -> Void
    @State private var editingVolume: Double?

    var body: some View {
        let shownVolume = editingVolume ?? clip.volume

        Form {
            Section {
                Toggle("음소거", isOn: Binding(
                    get: { clip.isMuted },
                    set: { setAudio(clip.volume, $0) }
                ))
                LabeledContent {
                    // 손을 뗄 때만 반영해 실행 취소가 잘게 쌓이지 않게 한다.
                    Slider(
                        value: Binding(get: { shownVolume }, set: { editingVolume = $0 }),
                        in: 0 ... 1,
                        onEditingChanged: { isEditing in
                            if !isEditing, let editingVolume {
                                setAudio(editingVolume, clip.isMuted)
                                self.editingVolume = nil
                            }
                        }
                    )
                    .disabled(clip.isMuted)
                    Text(shownVolume, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                } label: {
                    Text("음량")
                }
            } footer: {
                Text("결과물(미리보기·내보내기)에 들어가는 이 클립의 소리입니다. 영상 클립은 영상에 담긴 소리입니다. 영상 소리를 줄이면 배경음악이 상대적으로 크게 들립니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
