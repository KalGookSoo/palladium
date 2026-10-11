import SwiftUI

/// 클립 소리의 크기와 음소거(#44). 트랙 전체는 트랙 이름 옆 스피커 버튼과 트랙 이름 우클릭 메뉴로 바꾼다.
/// 인스펙터 오디오 탭의 `Form` 안에 섹션으로 들어간다(#90).
/// 음량 키프레임(#67)이 있으면 `volume`은 재생 헤드 위치의 음량이고, 슬라이더로 바꾸면 그 위치의 키프레임이 된다.
struct AudioInspectorView<Keyframes: View>: View {
    let clip: Clip
    /// 보여줄 음량(재생 헤드 위치).
    let volume: Double
    /// 음량을 바꾼다. 음소거만 바꿀 때는 음량이 `nil`이다(키프레임이 생기지 않게).
    let setAudio: (Double?, Bool) -> Void
    @ViewBuilder var keyframes: Keyframes
    @State private var editingVolume: Double?

    var body: some View {
        let shownVolume = editingVolume ?? volume

        Section {
            Toggle("음소거", isOn: Binding(
                get: { clip.isMuted },
                set: { setAudio(nil, $0) }
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
            keyframes
        } footer: {
            Text("결과물(미리보기·내보내기)에 들어가는 이 클립의 소리입니다. 영상 클립은 영상에 담긴 소리입니다. 영상 소리를 줄이면 배경음악이 상대적으로 크게 들립니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
