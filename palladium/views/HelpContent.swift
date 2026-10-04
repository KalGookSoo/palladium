import Foundation

/// 도움말 창의 기능 안내 한 꼭지.
struct HelpTopic: Identifiable {
    let title: String
    let body: String

    var id: String {
        title
    }
}

/// 앱 안에 둔 도움말 내용. 단축키는 `ShortcutGuide`에서 가져와 툴팁과 같은 내용을 보여준다.
/// 기능이 바뀌면 이 내용과 `docs/use-cases/`를 함께 고친다.
enum HelpContent {
    static let topics: [HelpTopic] = [
        HelpTopic(
            title: "프로젝트",
            body: "시작 창에서 새 프로젝트(⌘N)를 만들거나 목록에서 더블클릭해 엽니다. 편집한 내용은 파일 > 저장(⌘S)으로 저장하고, 저장하지 않은 변경은 1분마다 백업되어 비정상 종료 뒤 다시 열 때 복구할 수 있습니다. 쓰지 않는 프로젝트는 시작 창에서 우클릭 > 삭제로 지웁니다(원본 미디어 파일은 지우지 않습니다)."
        ),
        HelpTopic(
            title: "미디어 가져오기",
            body: "파일 > 가져오기(⌘I)나 툴바 버튼으로 영상·오디오·이미지를 여러 개 고르거나, Finder에서 미디어 패널·미리보기로 끌어다 놓습니다. 원본은 복사하지 않고 제자리에서 참조합니다. 이미 가져온 파일은 건너뛰고, 가져오지 못한 파일은 이유와 함께 알려 줍니다."
        ),
        HelpTopic(
            title: "원본 정리",
            body: "미디어 패널에서 원본을 고르고 F2로 이름을 바꿉니다(프로젝트 안의 이름만 바뀝니다). 우클릭으로 색상 레이블·태그를 붙이고, 새 폴더 버튼으로 폴더를 만들어 원본을 끌어다 넣습니다. 검색창은 이름과 태그를, 필터 메뉴는 색상 레이블로 원본을 거릅니다."
        ),
        HelpTopic(
            title: "타임라인 편집",
            body: "미디어 패널의 원본을 타임라인으로 끌어다 놓으면 클립이 됩니다. 기본은 삽입(뒤 클립을 밀어냄)이고 ⌘를 누른 채 놓으면 덮어씁니다. 위쪽 영상 트랙은 아래 트랙 위에 겹쳐 보입니다. 클립을 끌어 옮기고, ⌫로 지우고, ⇧⌫로 지운 자리를 메우고, ⌘B로 재생 헤드에서 자릅니다. ⌘·⇧ 클릭으로 여러 개를 고르고, 클립을 우클릭하면 메뉴가 열립니다."
        ),
        HelpTopic(
            title: "시퀀스",
            body: "한 프로젝트 안에서 통합본·하이라이트처럼 결과물을 여러 개 만듭니다. 타임라인 위의 시퀀스 이름을 눌러 바꾸기·새로 만들기·이름 변경·삭제를 합니다. 원본은 모든 시퀀스가 함께 씁니다."
        ),
        HelpTopic(
            title: "미리보기",
            body: "미디어 패널에서 원본을 더블클릭하면 미리보기에서 엽니다. Space로 재생/일시정지, ←/→로 한 프레임씩 이동합니다. 오른쪽 아래 스피커 버튼과 슬라이더는 지금 듣는 소리만 바꿉니다. 오른쪽 위 버튼으로 타임라인을 접고 폅니다."
        ),
        HelpTopic(
            title: "실행 취소",
            body: "가져오기·원본 정리·클립 편집·시퀀스와 폴더 변경은 모두 편집 > 실행 취소(⌘Z)와 다시 실행(⇧⌘Z)으로 되돌릴 수 있습니다."
        ),
    ]
}

/// 도움말 검색. 검색어가 비어 있거나 공백뿐이면 모두 일치한다.
struct HelpSearch {
    let query: String

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    func matches(_ topic: HelpTopic) -> Bool {
        trimmedQuery.isEmpty || topic.title.localizedStandardContains(trimmedQuery) || topic.body.localizedStandardContains(trimmedQuery)
    }

    func matches(_ entry: ShortcutGuideEntry) -> Bool {
        trimmedQuery.isEmpty
            || entry.title.localizedStandardContains(trimmedQuery)
            || entry.summary.localizedStandardContains(trimmedQuery)
            || entry.keys?.localizedStandardContains(trimmedQuery) == true
    }
}
