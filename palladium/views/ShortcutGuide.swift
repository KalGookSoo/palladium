/// 단축키 하나와 그 설명. 툴팁과 단축키 목록 창이 같은 내용을 보여주도록 `ShortcutGuide` 한곳에서 관리한다.
struct ShortcutGuideEntry: Identifiable {
    let title: String
    let summary: String
    /// 단축키가 없으면 `nil`.
    let keys: String?

    var id: String {
        title
    }

    /// 툴팁 문구. 예: "재생/일시정지 — 미리보기를 재생하거나 멈춥니다 (Space)"
    var helpText: String {
        guard let keys else { return "\(title) — \(summary)" }
        return "\(title) — \(summary) (\(keys))"
    }
}

/// 앱의 고정 단축키. 사용자가 바꿀 수 없다(커스텀 키맵은 보류 기능).
enum ShortcutGuide {
    static let openProjectList = ShortcutGuideEntry(title: "프로젝트 목록 열기", summary: "시작 창을 엽니다", keys: "⇧⌘1")
    static let newProject = ShortcutGuideEntry(title: "새 프로젝트 만들기", summary: "이름을 정해 새 프로젝트를 만듭니다(시작 창)", keys: "⌘N")
    static let save = ShortcutGuideEntry(title: "저장", summary: "저장하지 않은 변경을 저장합니다", keys: "⌘S")
    static let close = ShortcutGuideEntry(title: "닫기", summary: "편집 창을 닫습니다", keys: "⌘W")
    static let importMedia = ShortcutGuideEntry(title: "가져오기", summary: "영상·오디오·이미지 파일을 프로젝트로 가져옵니다", keys: "⌘I")
    static let export = ShortcutGuideEntry(title: "내보내기", summary: "편집한 영상을 파일로 내보냅니다", keys: "⌘E")
    static let aspectRatio = ShortcutGuideEntry(title: "화면비", summary: "결과물의 화면비를 고릅니다", keys: nil)

    static let toggleMediaPanel = ShortcutGuideEntry(title: "미디어 패널 보기/가리기", summary: "왼쪽 미디어 패널을 열고 닫습니다", keys: "⌃⌘S")
    static let toggleTimeline = ShortcutGuideEntry(title: "타임라인 보기/가리기", summary: "미리보기 아래 타임라인을 열고 닫습니다", keys: "⌥⌘2")
    static let toggleInspector = ShortcutGuideEntry(title: "인스펙터 보기/가리기", summary: "오른쪽 인스펙터를 열고 닫습니다", keys: "⌥⌘I")

    static let playPause = ShortcutGuideEntry(title: "재생/일시정지", summary: "미리보기를 재생하거나 멈춥니다", keys: "Space")
    static let previousFrame = ShortcutGuideEntry(title: "이전 프레임", summary: "한 프레임 뒤로 이동합니다", keys: "←")
    static let nextFrame = ShortcutGuideEntry(title: "다음 프레임", summary: "한 프레임 앞으로 이동합니다", keys: "→")
    static let narration = ShortcutGuideEntry(title: "내레이션 녹음", summary: "마이크로 내레이션을 녹음합니다(준비 중)", keys: nil)

    static let zoomInTimeline = ShortcutGuideEntry(title: "타임라인 확대", summary: "타임라인을 더 자세히 봅니다", keys: "⌘=")
    static let zoomOutTimeline = ShortcutGuideEntry(title: "타임라인 축소", summary: "타임라인을 더 넓게 봅니다", keys: "⌘-")

    static let renameAsset = ShortcutGuideEntry(title: "원본 이름 변경", summary: "미디어 패널에서 고른 원본의 이름을 바꿉니다", keys: "F2")
    static let filterMedia = ShortcutGuideEntry(title: "필터", summary: "색상 레이블로 원본을 거릅니다", keys: nil)

    static let showShortcuts = ShortcutGuideEntry(title: "단축키 목록", summary: "모든 단축키를 봅니다", keys: "⌘/")

    /// 단축키 목록 창에 보여줄 묶음. 단축키가 없는 항목은 넣지 않는다.
    static let sections: [(title: String, entries: [ShortcutGuideEntry])] = [
        ("파일", [openProjectList, newProject, save, close, importMedia, export]),
        ("보기", [toggleMediaPanel, toggleTimeline, toggleInspector, zoomInTimeline, zoomOutTimeline]),
        ("재생", [playPause, previousFrame, nextFrame]),
        ("편집", [renameAsset]),
        ("도움말", [showShortcuts]),
    ]
}
