---
title: Swift 코딩 컨벤션
nav_order: 7
---

# palladium Swift 코딩 컨벤션

## 목적

이 문서는 palladium macOS 네이티브 앱을 개발할 때 따를 Swift 코딩 컨벤션을 정의한다.
별도의 커스텀 규칙을 만들지 않고, Apple 공식 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)를 그대로 따른다.

## 핵심 원칙

- **사용하는 곳에서의 명확성이 간결함보다 중요하다.** 이름이 길어지더라도, 호출하는 코드를 읽었을 때 무슨 일이 일어나는지 명확해야 한다.
- **모든 선언에는 문서화 주석을 남긴다.** `///`로 시작하는 문서 주석을 타입, 메서드, 속성에 작성한다.
- **모호함보다는 명확함을 우선한다.** 짧지만 애매한 이름보다, 길더라도 뜻이 분명한 이름을 쓴다.

## 대소문자 규칙

| 대상                         | 규칙                          | 예시                                             |
|----------------------------|-----------------------------|------------------------------------------------|
| 타입, 프로토콜                   | UpperCamelCase              | `Clip`, `Codable`, `Timeline`                  |
| 변수, 상수, 함수, 메서드, enum case | lowerCamelCase              | `trimStartSeconds`, `func exportVideo()`, `.mp4` |
| 전역 상수                      | lowerCamelCase (특별한 접두사 없음) | `let defaultFrameRate = 30`                    |

## 네이밍

### 필요한 단어는 남기고, 불필요한 단어는 뺀다

타입 정보에서 이미 드러나는 단어는 이름에서 뺀다.

```swift
// 지양
func remove(element: Element) -> Element

// 권장
func remove(_ member: Element) -> Element
```

### 역할에 맞는 이름을 쓴다

타입이 아니라 그 값이 하는 역할을 기준으로 이름을 짓는다.

```swift
// 지양
var string: String

// 권장
var name: String
```

### 유창하게 읽히도록 이름을 짓는다

메서드 호출부가 문장처럼 읽혀야 한다.

```swift
clipRepository.insert(clip, at: sortOrder)
clips.removeAll(where: { $0.duration == 0 })
```

### Boolean은 단정문처럼 읽히게 짓는다

```swift
var isEmpty: Bool
var hasSubtitles: Bool
func contains(_ element: Element) -> Bool
```

### 부수효과가 있는지 없는지에 따라 동사/명사를 구분한다

원본을 바꾸는(mutating) 메서드는 동사형, 새 값을 반환하는(nonmutating) 메서드는 형용사/명사형이나 `ed`/`ing`을 붙인다.

```swift
// mutating (원본을 바꿈)
array.sort()
array.append(item)

// nonmutating (새 값 반환)
let sorted = array.sorted()
let appended = array + [item]
```

이 프로젝트에서는 예를 들어 `Clip`을 복제할 때 `duplicate()`(새 인스턴스 반환)와 `applyDuplicate()`(현재 인스턴스를 변경) 같은 식으로 구분한다.

### 커맨드와 쿼리를 엄격히 분리한다 (CQS)

하나의 함수/메서드는 "상태를 바꾸는 커맨드"이거나 "값을 반환하는 쿼리"여야지, 둘을 동시에 하지 않는다.

- 커맨드는 반환값이 없거나(`Void`), 있어도 부수효과의 결과를 확인하는 용도 이상으로 쓰지 않는다. 부수효과는 이름과 문서 주석만 보고도 무엇이 바뀌는지 예측할 수 있어야 하고, 숨겨진 부수효과(다른 프로퍼티까지 같이 바뀐다거나 파일 시스템에 몰래 쓴다거나)는 두지 않는다.
- 쿼리는 부수효과 없이 값만 반환하며, 같은 입력에는 항상 같은 결과를 내는 순수 함수에 가깝게 유지한다.

palladium은 추후 MCP(Model Context Protocol)를 통해 AI 에이전트가 편집 기능을 직접 호출할 수 있게 열 계획이다([기능명세서](video-editing-functional-spec.md) 참고). 각 기능이 커맨드/쿼리로 엄격히 분리되고 부수효과가 예측 가능해야, 나중에 이 함수들을 그대로 MCP 툴로 노출했을 때 에이전트가 안전하게 호출할 수 있다. 이 원칙은 나중에 리팩터링으로 끼워 맞추는 게 아니라 각 기능을 처음 구현하는 시점부터 지킨다.

### 프로토콜 이름

- 어떤 능력을 나타내는 프로토콜: `-able`/`-ible` 접미사 (`Codable`, `Equatable`)
- 무엇인지를 나타내는 프로토콜: 명사 (`Collection`, `ClipRepository`)

### 인자 레이블(argument label)

- 인자를 구분할 필요가 없으면 레이블을 생략한다: `min(a, b)`
- 그 외에는 레이블을 붙여서 호출부가 문장처럼 읽히게 한다: `Clip(trimStart: 10, trimEnd: 20)`
- 팩토리 메서드는 `make`로 시작한다: `static func makeDefaultProject() -> VideoProject`

## 접근 제어

- 기본값은 `private`(또는 `fileprivate`)로 최대한 좁게 잡는다.
- 다른 타입/모듈에서 실제로 필요할 때만 `internal`(기본값, 생략 가능) 또는 `public`으로 넓힌다.
- SwiftData `@Model` 클래스의 저장 프로퍼티처럼 외부에서 읽고 써야 하는 경우를 제외하면, 계산이나 헬퍼 로직은 `private`으로 감춘다.

## 불변성

- 값이 바뀌지 않으면 `var`보다 `let`을 쓴다.
- 구조체(`struct`)를 기본으로 쓰고, SwiftData `@Model`처럼 참조 타입(`class`)이 꼭 필요한 경우에만 클래스를 쓴다.

## 코드 구성

- 프로토콜 conformance는 `extension`으로 분리한다.

```swift
struct Clip {
    var sourceURL: URL
    var trimRange: ClosedRange<TimeInterval>
}

extension Clip: Codable {}
extension Clip: Hashable {}
```

- 파일 안에서 섹션을 나눌 때는 `// MARK: -`를 쓴다.

```swift
// MARK: - Lifecycle

// MARK: - Actions
```

- 조건에서 일찍 빠져나갈 때는 `if`보다 `guard`를 우선한다. 실패/예외 케이스를 먼저 처리하고 빠져나가면, 나머지 코드는 "성공한 경우"만 다루면 되어 인덴트가 한 단 줄어든다.

```swift
guard let project = project else { return }
```

```swift
// 지양
func requestDelete(_ clip: Clip) {
    if usedBy.isEmpty {
        delete(clip)
    } else {
        pendingDeletion = (clip, usedBy)
    }
}

// 권장
func requestDelete(_ clip: Clip) {
    guard !usedBy.isEmpty else {
        delete(clip)
        return
    }
    pendingDeletion = (clip, usedBy)
}
```

- 표현식이 깊게 중첩되면(특히 클로저 안에 클로저), modifier 인자 등에 바로 넘기지 말고 이름 있는 지역변수로 먼저 뽑아서 인덴트를 줄인다. 여러 곳에서 재사용하지 않는 한 프로퍼티(특히 계산 프로퍼티)로 끌어올리지 않는다 — 스코프는 필요한 만큼만 넓힌다. 한 곳에서만 쓰는 값은 프로퍼티로 미리 선언해두기보다, 쓰는 자리 바로 앞에 지역변수로 두거나 파라미터를 받는 순수 함수로 남겨서, 선언을 보려고 파일 위쪽으로 스크롤하지 않아도 되게 한다.

```swift
// 지양 — modifier 인자 안에 Binding(get:set:)가 그대로 중첩됨
.confirmationDialog(
    "...",
    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
    presenting: pendingDeletion
) { ... }

// 권장 — 쓰는 자리 바로 위(예: body 안)에서 지역변수로 먼저 뽑는다
let isPendingDeletionPresented = Binding<Bool>(
    get: { pendingDeletion != nil },
    set: { if !$0 { pendingDeletion = nil } }
)
...
.confirmationDialog("...", isPresented: isPendingDeletionPresented, presenting: pendingDeletion) { ... }
```

이 프로젝트에서 `Binding(get:set:)`는 항상 이렇게 필요한 스코프(대부분 `body` 안)에 지역적으로 선언한다 — `private var`로 끌어올린 사례는 없다.

## 문서화 주석

공개 타입/메서드/속성에는 `///` 문서 주석을 남긴다.

```swift
/// 저장된 클립을 이름 기준으로 조회한다.
/// - Parameter name: 검색할 클립 이름.
/// - Returns: 일치하는 클립. 없으면 `nil`.
func findClip(named name: String) -> Clip?
```

## 포맷팅

들여쓰기 정리는 Xcode의 `Editor > Structure > Re-Indent` (`Ctrl + I`)로도 할 수 있지만, 줄바꿈/공백/import 정렬 같은 세부 포맷팅까지 일관되게 맞추기 위해 **SwiftFormat**을 사용한다.

### 설치

```bash
brew install swiftformat
```

### 설정

저장소 루트의 `.swiftformat` 파일에 규칙을 정의한다(아직 생성 전이라면 먼저 만든다). 커스텀 규칙은 최소로 두고, 프로젝트의 Swift 버전(`SWIFT_VERSION = 5.0`)과 Xcode 기본 들여쓰기(4 스페이스)만 명시한다.

```text
--swiftversion 5.0
--indent 4
```

### 사용

```bash
# 포맷팅 위반 여부만 확인 (파일을 바꾸지 않음)
swiftformat --lint palladium

# 실제로 포맷 적용
swiftformat palladium
```

커밋 전에 `swiftformat --lint`로 확인하는 것을 권장한다. 반복적으로 수행하려면 Xcode의 `Build Phases`에 `swiftformat "$SRCROOT"` 같은 Run Script 단계를 추가해서 빌드할 때마다 자동으로 정리되게 할 수도 있다 (선택 사항).
