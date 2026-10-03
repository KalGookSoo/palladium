#if DEBUG
    import SwiftUI

    extension FocusedValues {
        @Entry var makeUnsavedChange: (() -> Void)?
    }

    /// 디버그 빌드 전용 메뉴. 아직 프로젝트 내용을 바꾸는 편집 기능이 없어,
    /// 저장하지 않은 변경 상태(저장 메뉴, 닫기 버튼의 점, 닫기·종료 확인 창)를 직접 확인할 수 있게 한다.
    struct DebugCommands: Commands {
        @FocusedValue(\.makeUnsavedChange) private var makeUnsavedChange

        var body: some Commands {
            CommandMenu("디버그") {
                Button("저장하지 않은 변경 만들기") {
                    makeUnsavedChange?()
                }
                .disabled(makeUnsavedChange == nil)
            }
        }
    }
#endif
