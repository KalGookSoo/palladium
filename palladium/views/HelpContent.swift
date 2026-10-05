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
            body: "미디어 패널의 원본을 타임라인으로 끌어다 놓으면 클립이 됩니다. 클립 위에 놓으면 가까운 클립 경계에 끼워 넣고 뒤 클립을 밀며, 끄는 동안 들어갈 자리와 밀린 모습이 미리 보입니다. 놓을 클립의 끝은 다른 클립 경계·재생 헤드에 자석처럼 붙습니다. 결과물(시퀀스)은 하나이고 트랙은 그 안의 층입니다. 영상 1이 메인이고 그 위 영상 트랙은 겹쳐 보입니다. 트랙은 트랙 이름을 우클릭해 직접 추가하고, 빈 트랙은 지웁니다. 클립을 끌어 옮기고, ⌫로 지우고, ⇧⌫로 지운 자리를 메웁니다. 중간에 넣으려면 눈금자를 눌러 재생 헤드(파란 세로선)를 옮긴 뒤 편집 > 클립 분할(⌘B)로 나눕니다. ⌘·⇧ 클릭으로 여러 개를 고르고, Esc로 선택을 풉니다. 클립 보기 메뉴에서 필름스트립·파형을 켜고 끕니다. 클립 끝을 끌면 트림되고 뒤 클립이 따라오며, ⌥를 누르면 정밀하게 조정합니다(인스펙터 트림 탭에서 시간을 입력해도 됩니다). M으로 재생 헤드에 마커를 두고, 마커 메뉴나 눈금자의 마커를 눌러 그 시점으로 갑니다."
        ),
        HelpTopic(
            title: "시퀀스",
            body: "한 프로젝트 안에서 통합본·하이라이트처럼 결과물을 여러 개 만듭니다. 타임라인 위의 시퀀스 이름을 눌러 바꾸기·새로 만들기·이름 변경·삭제를 합니다. 원본은 모든 시퀀스가 함께 씁니다."
        ),
        HelpTopic(
            title: "오버레이(이미지·영상 얹기)",
            body: "트랙 이름을 우클릭해 영상 트랙을 추가하고, 그 트랙에 이미지나 영상을 끌어다 놓으면 아래 영상 위에 겹쳐 보입니다. 클립을 고르면 미리보기에 테두리가 생기며, 안을 끌어 옮기고 오른쪽 아래 손잡이로 크기를 바꿉니다. 인스펙터 트랜스폼 탭에서 위치·크기·불투명도를 숫자로도 바꿀 수 있습니다. 보이는 시간은 클립 끝을 끌어 정합니다."
        ),
        HelpTopic(
            title: "소리 조절",
            body: "결과물에 들어가는 소리는 클립을 고른 뒤 인스펙터 오디오 탭에서 음량과 음소거를, 트랙 전체는 트랙 이름 옆 스피커 버튼(음소거)과 트랙 이름 우클릭 > 트랙 음량으로 바꿉니다. 영상 클립의 소리도 같은 방식입니다. 미리보기 오른쪽 아래 음량은 지금 듣는 소리만 바꿉니다."
        ),
        HelpTopic(
            title: "미리보기",
            body: "미리보기는 타임라인의 결과물(시퀀스)을 재생합니다. Space로 재생/일시정지, ←/→로 한 프레임씩 이동하고, 재생 헤드를 옮기면 미리보기도 따라갑니다. 넣기 전에 원본을 보려면 미디어 패널에서 더블클릭해 훑어보기 창을 엽니다. 오른쪽 아래 스피커 버튼과 슬라이더는 지금 듣는 소리만 바꾸고, 오른쪽 위 버튼으로 타임라인을 접고 폅니다."
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
