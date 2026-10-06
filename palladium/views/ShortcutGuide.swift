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
    static let batchExport = ShortcutGuideEntry(title: "여러 시퀀스 내보내기", summary: "고른 시퀀스들을 한 폴더에 차례로 내보냅니다", keys: "⇧⌘E")
    static let aspectRatio = ShortcutGuideEntry(title: "화면비", summary: "결과물의 화면비를 고릅니다", keys: nil)

    static let toggleMediaPanel = ShortcutGuideEntry(title: "미디어 패널 보기/가리기", summary: "왼쪽 미디어 패널을 열고 닫습니다", keys: "⌃⌘S")
    static let toggleTimeline = ShortcutGuideEntry(title: "타임라인 보기/가리기", summary: "미리보기 아래 타임라인을 열고 닫습니다", keys: "⌥⌘2")
    static let toggleInspector = ShortcutGuideEntry(title: "인스펙터 보기/가리기", summary: "오른쪽 인스펙터를 열고 닫습니다", keys: "⌥⌘I")

    static let playPause = ShortcutGuideEntry(title: "재생/일시정지", summary: "미리보기를 재생하거나 멈춥니다", keys: "Space")
    static let previousFrame = ShortcutGuideEntry(title: "이전 프레임", summary: "한 프레임 뒤로 이동합니다", keys: "←")
    static let nextFrame = ShortcutGuideEntry(title: "다음 프레임", summary: "한 프레임 앞으로 이동합니다", keys: "→")
    static let narration = ShortcutGuideEntry(title: "내레이션 녹음 시작/정지", summary: "재생 헤드부터 영상을 재생하며 마이크로 내레이션을 녹음하고, 멈추면 오디오 트랙에 놓습니다", keys: "R")

    static let zoomInTimeline = ShortcutGuideEntry(title: "타임라인 확대", summary: "타임라인을 더 자세히 봅니다", keys: "⌘=")
    static let zoomOutTimeline = ShortcutGuideEntry(title: "타임라인 축소", summary: "타임라인을 더 넓게 봅니다", keys: "⌘-")

    static let undo = ShortcutGuideEntry(title: "실행 취소", summary: "마지막 편집을 되돌립니다", keys: "⌘Z")
    static let redo = ShortcutGuideEntry(title: "다시 실행", summary: "되돌린 편집을 다시 합니다", keys: "⇧⌘Z")
    static let deleteClips = ShortcutGuideEntry(title: "삭제", summary: "고른 클립을 지우고 그 자리는 비워 둡니다", keys: "⌫")
    static let rippleDeleteClips = ShortcutGuideEntry(title: "리플 삭제", summary: "고른 클립을 지우고 뒤 클립을 당겨 틈을 메웁니다", keys: "⇧⌫")
    static let splitAtPlayhead = ShortcutGuideEntry(title: "클립 분할", summary: "재생 헤드(파란 세로선) 위치에서 고른 클립(없으면 재생 헤드에 걸친 모든 클립)을 둘로 나눕니다", keys: "⌘B")
    static let copyClips = ShortcutGuideEntry(title: "복사", summary: "고른 클립(또는 자막·마스크)을 앱 안 클립보드에 담습니다", keys: "⌘C")
    static let cutClips = ShortcutGuideEntry(title: "잘라내기", summary: "고른 클립을 클립보드에 담고 지운 자리를 메웁니다", keys: "⌘X")
    static let pasteClips = ShortcutGuideEntry(title: "붙여넣기", summary: "재생 헤드에 붙입니다. 클립은 경계에 끼워 넣고 뒤 클립을 밀며, 다른 시퀀스에도 붙일 수 있습니다", keys: "⌘V")
    static let duplicateClips = ShortcutGuideEntry(title: "복제", summary: "고른 클립 바로 뒤에 같은 클립을 넣습니다(클립보드는 그대로)", keys: "⌘D")
    static let addMarker = ShortcutGuideEntry(title: "재생 헤드에 마커 추가", summary: "나중에 다시 찾을 시점에 책갈피를 둡니다", keys: "M")
    static let addSubtitle = ShortcutGuideEntry(title: "재생 헤드에 자막 추가", summary: "재생 헤드부터 3초 동안 나오는 자막을 자막 트랙에 둡니다", keys: "T")
    static let preciseTrim = ShortcutGuideEntry(title: "정밀 트림", summary: "클립 끝을 끌 때 이동량을 줄여 프레임 단위로 맞춥니다", keys: "⌥ 누른 채 끌기")
    static let rollTrim = ShortcutGuideEntry(title: "롤 트림", summary: "클립 끝을 끌어 맞닿은 이웃 클립과의 경계를 옮깁니다(전체 길이 그대로)", keys: "⌘ 누른 채 끝 끌기")
    static let slipTrim = ShortcutGuideEntry(title: "슬립 트림", summary: "클립 위치·길이는 두고 원본에서 쓰는 구간만 옮깁니다", keys: "⌘ 누른 채 클립 끌기")
    static let slideTrim = ShortcutGuideEntry(title: "슬라이드 트림", summary: "클립을 옮기며 맞닿은 앞뒤 클립의 경계를 함께 바꿉니다", keys: "⇧ 누른 채 클립 끌기")
    static let deselect = ShortcutGuideEntry(title: "선택 해제", summary: "끄는 중인 편집을 취소하거나, 고른 클립·원본 선택을 한 단계씩 풉니다", keys: "Esc")
    static let toggleFilmstrip = ShortcutGuideEntry(title: "필름스트립 보기", summary: "영상·이미지 클립 안에 프레임을 그립니다", keys: nil)
    static let toggleWaveform = ShortcutGuideEntry(title: "오디오 파형 보기", summary: "소리가 있는 클립 안에 파형을 그립니다", keys: nil)
    static let selectAllClips = ShortcutGuideEntry(title: "모든 클립 선택", summary: "타임라인의 클립을 모두 고릅니다", keys: "⌘A")
    static let toggleClipSelection = ShortcutGuideEntry(title: "선택에 더하기/빼기", summary: "클립을 하나씩 더 고르거나 뺍니다", keys: "⌘ 클릭")
    static let extendClipSelection = ShortcutGuideEntry(title: "범위 선택", summary: "같은 트랙에서 고른 클립까지 사이를 모두 고릅니다", keys: "⇧ 클릭")
    static let rename = ShortcutGuideEntry(title: "이름 변경", summary: "타임라인에서 고른 클립의 별칭을, 미디어 패널에 포커스가 있으면 고른 원본의 이름을 바꿉니다", keys: "F2")
    static let trimSheet = ShortcutGuideEntry(title: "트림…", summary: "고른 클립(미디어 패널에 포커스가 있으면 항목)을 트림 창에서 원본 전체를 보며 줄이고 늘리고 자릅니다", keys: "⌘T")
    static let trimNudge = ShortcutGuideEntry(title: "트림 구간 미세 조정", summary: "트림 창에서 마지막으로 잡은 손잡이를 0.1초씩, ⇧와 함께 1초씩 옮깁니다", keys: "↑/↓ (트림 창)")
    static let deleteAsset = ShortcutGuideEntry(title: "원본 삭제", summary: "미디어 패널에서 고른 원본을 프로젝트에서 뺍니다(쓰는 클립도 함께, 원본 파일은 남음)", keys: "⌫ (미디어 패널)")
    static let filterMedia = ShortcutGuideEntry(title: "필터", summary: "색상 레이블로 원본을 거릅니다", keys: nil)

    static let showShortcuts = ShortcutGuideEntry(title: "단축키 목록", summary: "도움말 창에서 모든 단축키를 봅니다", keys: "⌘/")
    static let showHelp = ShortcutGuideEntry(title: "palladium 도움말", summary: "기능 안내와 단축키를 보고 검색합니다", keys: "⇧⌘/")

    /// 단축키 목록 창에 보여줄 묶음. 단축키가 없는 항목은 넣지 않는다.
    static let sections: [(title: String, entries: [ShortcutGuideEntry])] = [
        ("파일", [openProjectList, newProject, save, close, importMedia, export, batchExport]),
        ("보기", [toggleMediaPanel, toggleTimeline, toggleInspector, zoomInTimeline, zoomOutTimeline]),
        ("재생", [playPause, previousFrame, nextFrame, narration]),
        ("편집", [undo, redo, rename, trimSheet, trimNudge, deleteAsset]),
        ("타임라인", [deleteClips, rippleDeleteClips, cutClips, copyClips, pasteClips, duplicateClips, splitAtPlayhead, selectAllClips, toggleClipSelection, extendClipSelection, deselect, addMarker, addSubtitle, preciseTrim, rollTrim, slipTrim, slideTrim]),
        ("도움말", [showHelp, showShortcuts]),
    ]
}
