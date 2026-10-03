---
title: 네이티브 스타일 가이드
nav_order: 6
---

# palladium 네이티브 스타일 가이드

## 목적

이 문서는 palladium 앱의 기본 디자인 체계를 정의한다. 목표는 별도의 커스텀 디자인 시스템을 만들지 않고, **macOS 기본 빌트인 앱(Finder, 사진, 음악 등)과 동일한 느낌의 절제된 네이티브 스타일**을 따르는 것이다. 편집 도구다운 정보 밀도는 필요하지만, 이를 커스텀 컬러 팔레트나 커스텀 컴포넌트가 아니라 **시스템 기본값**으로 달성한다.

구현은 SwiftUI 표준 컴포넌트와 SF Symbols를 기준으로 한다. 커스텀 컴포넌트 라이브러리를 따로 만들지 않고, `NavigationSplitView`, `List`, `Table`, `.toolbar`, `.inspector` 같은 macOS 표준 컨테이너/컨트롤을 기본 스타일 그대로 사용한다.

## 디자인 원칙

- **시스템을 따른다**: 색상, 폰트, 간격, 모양 전부 macOS 표준값을 그대로 쓴다. 커스텀 값은 기능상 꼭 필요한 경우에만 최소로 둔다.
- **꾸미지 않는다**: 그림자, 굵은 보더, 강한 색면 같은 장식 요소를 별도로 만들지 않는다.
- **라이트/다크 모두 지원**: tempo(항상 다크 고정)와 달리 palladium은 macOS 시스템 설정(라이트/다크/자동)을 그대로 따른다 — Finder, 사진, 음악 등 macOS 기본 앱들이 그렇듯이. 라이트/다크 분기 코드를 직접 작성하지 않는다: 시스템 시맨틱 컬러를 쓰면 두 모드 모두에서 자동으로 올바른 값이 나온다.
- **사용자의 강조색을 존중한다**: 앱 고유의 브랜드 컬러를 강조색으로 하드코딩하지 않는다. `Color.accentColor`(macOS 시스템 설정 > 손쉬운 사용 > 디스플레이의 "강조 색상"을 그대로 반영)를 쓴다 — 이것이 "빌트인 앱처럼 보인다"는 요구사항의 핵심이다. (참고: [UI 레이아웃](ui-layout.md)의 와이어프레임에 쓰인 보라색은 어디까지나 목업 표시용 placeholder이며, 실제 구현에서는 시스템 강조색으로 대체한다.)
- **기능 우선**: 장식보다 미리보기 화면과 타임라인의 클립 정보가 먼저 보여야 한다.

## 컬러

커스텀 팔레트를 정의하지 않는다. 배경, 표면, 텍스트, 보더는 모두 macOS 시맨틱 컬러를 그대로 사용한다.

| 용도 | 시스템 컬러 |
|---|---|
| 창/캔버스 배경 | `Color(nsColor: .windowBackgroundColor)` |
| 패널/사이드바 배경 | `Color(nsColor: .controlBackgroundColor)` 또는 `.regularMaterial`/`.sidebar` 머티리얼 |
| 구분선 | `Color(nsColor: .separatorColor)` |
| 선택 상태 배경 | `Color(nsColor: .selectedContentBackgroundColor)` |
| 본문 텍스트 | `Color.primary` |
| 보조 텍스트 | `Color.secondary` |
| 강조(버튼, 재생 헤드, 선택 표시) | `Color.accentColor` |

타임라인의 트랙 종류(영상/오디오/자막/오버레이)는 색으로 구분하지 않는다. 클립 바탕은 중립색(`.quaternary`, 선택 시 `.tertiary`)으로 두고, 종류는 트랙 레이블("영상 1", "오디오 1")과 클립 내용 모양(영상은 필름스트립, 오디오는 파형)으로 드러낸다. 이렇게 해야 강조색(선택 테두리)이 트랙 색과 겹쳐 선택이 묻히지 않는다. 필름스트립·파형이 생기기 전까지는 종류 아이콘(`film`, `waveform`)이 그 자리를 대신한다.

## 타입 시스템

커스텀 폰트를 도입하지 않는다. 시스템 폰트(San Francisco)를 그대로 쓰고, SwiftUI 텍스트 스타일(`.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.body`, `.callout`, `.footnote`, `.caption`)을 용도에 맞게 사용한다.

| 용도 | 텍스트 스타일 |
|---|---|
| 창/섹션 제목 | `.title2` / `.headline` |
| 본문 | `.body` |
| 보조 설명, 메타데이터 | `.footnote` / `.caption` |
| 타임코드(재생 시간, 트림 지점) | `.body` 이상 + `.monospacedDigit()` |

타임코드처럼 숫자가 계속 바뀌는 곳에는 `.monospacedDigit()`을 적용해 자릿수가 흔들리지 않게 한다. 이 외에 별도 mono 폰트나 커스텀 폰트 스택은 두지 않는다.

## 간격과 레이아웃

커스텀 spacing scale을 정의하지 않는다. SwiftUI 기본 padding과 macOS 표준 레이아웃 컨테이너의 기본 inset을 그대로 따른다.

- 메인 화면은 `NavigationSplitView`(3컬럼: 미디어 패널 · 콘텐츠 · 인스펙터)로 구성한다 — 직접 `HSplitView`로 재구현하지 않는다. 자세한 섹션 구성은 [UI 레이아웃](ui-layout.md) 참고.
- 인스펙터는 macOS 14+ 표준 `.inspector(isPresented:)` modifier로 붙인다.
- 리스트 형태 화면(미디어 패널의 클립 목록 등)은 `List`(`.listStyle(.sidebar)`) 또는 구조화된 데이터가 필요하면 `Table`을 그대로 쓴다.
- 타임라인처럼 표준 컨테이너로 표현하기 어려운 화면에서만 최소한으로 커스텀 레이아웃(`Canvas`, 커스텀 `Layout`)을 쓴다.

## Shape와 Elevation

- 커스텀 보더, radius, shadow 스케일을 정의하지 않는다.
- 패널 배경은 `.regularMaterial`/`.thinMaterial` 같은 시스템 머티리얼을 우선 사용한다 — Finder 사이드바나 음악 앱처럼 반투명 느낌을 시스템이 알아서 처리하게 둔다.
- 버튼, 그룹은 표준 SwiftUI 스타일(`.buttonStyle(.bordered)`, `.buttonStyle(.borderedProminent)`, `GroupBox`)이 제공하는 모양과 그림자를 그대로 쓴다.

## 기본 컴포넌트

| 용도 | SwiftUI 컴포넌트 |
|---|---|
| 전체 레이아웃 | `NavigationSplitView` |
| 툴바 | `.toolbar { ToolbarItemGroup }` |
| 인스펙터 | `.inspector(isPresented:)` |
| 목록 | `List`, `Table`, `Section` |
| 버튼 | `Button` (`.bordered`, `.borderedProminent`, `.plain`) |
| 입력 | `TextField`, `Slider`, `Stepper` |
| 선택/전환 | `Picker`(pop-up/segmented), `Toggle` |
| 구분선 | `Divider` |
| 액션 목록/메뉴 | `Menu`, `ContextMenu` |
| 시트(가져오기/내보내기 등) | `.sheet(isPresented:)` |

### 버튼

- 주요 실행(내보내기, 저장): `.borderedProminent`, tint는 `Color.accentColor`(시스템 강조색).
- 보조 동작(가져오기, 편집, 취소): `.bordered` 또는 `.plain`.
- 파괴적 동작(삭제): `.bordered` + `role: .destructive` (시스템이 자동으로 빨간색 처리).
- 예외 — 툴바 안의 버튼: 주요 실행이라도 `.borderedProminent`를 쓰지 않고 툴바 기본 스타일을 쓴다. 툴바에서 `.borderedProminent`는 다른 버튼보다 크게 그려져 버튼 크기가 어긋나기 때문이다. 버튼은 캡슐로 묶지 않고 모두 개별 버튼으로 둔다(항목 사이에 `ToolbarSpacer`). 묶는 기준이 모호하고, 묶으면 아이콘 정렬이 어긋나 보이기 때문이다.

## Iconography

아이콘은 SF Symbols를 사용한다. 커스텀 아이콘 세트를 도입하지 않는다.

| 기능 | SF Symbol |
|---|---|
| 가져오기 | `square.and.arrow.down` |
| 내보내기 | `square.and.arrow.up` |
| 재생 | `play.fill` |
| 일시정지 | `pause.fill` |
| 자르기(트림) | `scissors` |
| 실행 취소 / 다시 실행 | `arrow.uturn.backward` / `arrow.uturn.forward` |
| 마커 | `bookmark.fill` |
| 자막 | `captions.bubble.fill` |
| 이펙트 | `wand.and.stars` |
| 트랜스폼(위치/크기/회전) | `arrow.up.left.and.arrow.down.right` |
| 오디오/볼륨 | `speaker.wave.2.fill` |
| 음소거 | `speaker.slash.fill` |
| 확대(줌 인) / 축소(줌 아웃) | `plus.magnifyingglass` / `minus.magnifyingglass` |
| 설정 | `gearshape.fill` |

아이콘 크기와 굵기는 SF Symbols의 기본 `Font`/`imageScale` 연동을 그대로 따르고, 별도로 strokeWidth 같은 값을 지정하지 않는다. 아이콘 색은 현재 텍스트/tint 색을 따른다.

## 접근성

- 색상만으로 상태를 전달하지 않는다(트랙 종류는 레이블 텍스트와 아이콘·내용 모양으로, 클립 선택은 테두리 두께와 바탕 농도로도 구분한다).
- 아이콘 버튼에는 `accessibilityLabel`을 제공한다.
- VoiceOver, Reduce Motion, Increase Contrast 같은 시스템 접근성 설정을 존중한다.
- 키보드 단축키(스페이스바 재생/정지, 화살표 키 프레임 이동 등)를 지원해 트랙패드/마우스 없이도 조작 가능하게 한다 — macOS 프로 작업 도구의 기본 기대치다.

## 구현 기준

- 커스텀 `ViewModifier`/컴포넌트는 정말로 반복되는 경우에만 만들고, 그 안에서도 시스템 스타일(색상, 폰트, 컨트롤 스타일)을 감싸는 정도로만 쓴다.
- 화면마다 색상 hex 값이나 임의의 폰트 크기를 직접 쓰지 않는다. 이 문서에 정의된 색상 매핑과 표준 텍스트 스타일만 사용한다.
- 라이트/다크 분기 코드를 작성하지 않는다. 시스템 시맨틱 컬러와 `Color.accentColor`를 쓰면 두 모드 모두에서 자동으로 처리된다.

## 금지 규칙

- 커스텀 컬러 팔레트, 커스텀 폰트, 커스텀 shadow/보더 스케일을 새로 만들지 않는다.
- 앱 고유의 브랜드 강조색을 하드코딩하지 않는다 — 항상 `Color.accentColor`(시스템 강조색)를 쓴다.
- 표준 컨트롤 스타일을 임의로 재구현하지 않는다(예: 버튼이나 사이드바를 직접 그려서 만들지 않는다).
- 표준 UI 패턴(`NavigationSplitView`, 툴바, 인스펙터)을 벗어난 독자적인 창 레이아웃을 만들지 않는다.
