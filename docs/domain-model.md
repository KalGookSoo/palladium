---
title: 도메인 모델
nav_order: 9
---

# palladium 도메인 모델 (초안)

## 목적

프로젝트·미디어·시퀀스·트랙·클립이 무엇을 가지고 서로 어떻게 연결되는지, 각 타입이 무엇을 책임지는지 정리한다. 이 문서의 타입은 UI(#12~#17)와 이후 기능 구현이 모두 기대는 공통 기반이며, [테스트 전략](testing-strategy.md)의 원칙대로 View와 미디어 재생·합성 프레임워크에 의존하지 않는 순수 값 타입으로 구현한다.

## 엔티티 관계

```mermaid
classDiagram
    class Project {
        id: UUID
        name: String
        assets: Array~MediaAsset~
        sequences: Array~EditSequence~
    }
    class MediaAsset {
        id: UUID
        sourceURL: URL
        kind: MediaKind
        duration: CMTime
    }
    class EditSequence {
        id: UUID
        name: String
        tracks: Array~Track~
    }
    class Track {
        id: UUID
        kind: TrackKind
        clips: Array~Clip~
    }
    class Clip {
        id: UUID
        assetID: MediaAsset.ID
        sourceRange: CMTimeRange
        timelineStart: CMTime
    }
    Project "1" *-- "0..*" MediaAsset
    Project "1" *-- "1..*" EditSequence
    EditSequence "1" *-- "0..*" Track
    Track "1" *-- "0..*" Clip
    Clip ..> MediaAsset : assetID로 참조
```

## 타입별 책임

| 타입 | 책임 | 비고 |
|---|---|---|
| `Project` | 가져온 원본 미디어와 시퀀스를 담는 저장 단위 | 새 프로젝트는 빈 시퀀스 하나로 시작한다([프로젝트 저장/불러오기](use-cases/project-management.md)) |
| `MediaAsset` | 가져온 원본 파일 하나(영상/오디오/이미지)의 정보 | 미디어 패널에 보이는 항목. 타임라인 배치 정보는 갖지 않는다 |
| `EditSequence` | 독립된 편집 결과물 하나(통합본 또는 하이라이트) | Swift 표준 라이브러리의 `Sequence` 프로토콜과 이름이 겹치지 않도록 `EditSequence`로 짓는다 |
| `Track` | 시퀀스 안에서 클립이 시간순으로 놓이는 레인 하나 | `TrackKind`: `video`, `audio` |
| `Clip` | 원본의 어느 구간(`sourceRange`)을 타임라인의 어느 위치(`timelineStart`)에 놓을지 | 타임라인에서 차지하는 구간(`timelineRange`)은 저장하지 않고 계산한다 |

보조 타입:

- `MediaKind`: `video`, `audio`, `image`
- `TrackKind`: `video`, `audio`

## 설계 결정

### 원본(`MediaAsset`)과 타임라인 클립(`Clip`)을 분리한다

같은 원본을 타임라인에 여러 번 배치할 수 있어야 한다. 원본 정보를 클립마다 복사하지 않고 `MediaAsset` 한 곳에만 두며, `Clip`은 원본을 `assetID`로만 참조한다. 원본 파일 위치가 바뀌어도(relink) `MediaAsset` 하나만 고치면 된다.

### 시간은 `CMTime` / `CMTimeRange`로 표현한다

`Double`(초 단위)은 29.97fps 같은 프레임레이트에서 반올림 오차가 누적된다. `CMTime`은 시간을 분수(value/timescale)로 표현해 프레임 단위로 정확하고, 유즈케이스 문서의 커맨드/쿼리도 이미 `CMTime`을 기준으로 적혀 있다. `CMTime`이 속한 CoreMedia는 재생·합성을 담당하는 AVFoundation과 달리 값 타입만 담은 프레임워크라, 도메인 모델이 이를 import해도 순수성이 유지된다.

### 순수 값 타입으로 만든다

- 모든 도메인 타입은 `struct`/`enum`이다. 대입하면 복사되므로 한 곳의 변경이 다른 곳에 몰래 전파되지 않고, 실행 취소는 이전 값을 보관하는 것만으로 구현할 수 있다.
- `SwiftUI`와 `AVFoundation`을 import하지 않는다(`Foundation`, `CoreMedia`만 허용).
- 앱 타깃의 기본 격리가 `MainActor`이므로, 도메인 타입은 `nonisolated`로 선언해 테스트와 백그라운드 작업(내보내기 등)에서도 쓸 수 있게 한다.

### 규칙을 어기는 값은 만들어지지 않게 한다

불변식을 위반하는 값은 실패할 수 있는 이니셜라이저(`init?`)로 생성 단계에서 거부한다. 생성 이후에 "유효한지"를 매번 검사하지 않아도 되게 하기 위함이다.

## 불변식

| 대상 | 규칙 | 보장 방법 |
|---|---|---|
| `Clip` | `sourceRange`의 길이는 0보다 크다 | `init?`에서 거부 |
| `Track` | 같은 트랙의 클립끼리는 타임라인 구간이 겹치지 않는다 | 쿼리 `hasOverlappingClips`로 검사 |
| `Project` | 시퀀스가 최소 하나 있다 | 새 프로젝트 생성 시 빈 시퀀스 하나를 포함 |

각 불변식은 `palladiumTests`에 Swift Testing 유닛 테스트로 검증한다.

## 샘플 데이터

`#Preview`와 유닛 테스트가 함께 쓰는 샘플은 앱 타깃의 `palladium/domain/SampleData.swift` 한 곳에 둔다. `#Preview`는 앱 타깃 안에서 실행되므로 샘플이 앱 쪽에 있어야 하고, 테스트는 `@testable import palladium`으로 같은 샘플에 접근한다.

## 영속화(SwiftData) 경계

- 프로젝트 파일은 SwiftData 기반 자체 포맷으로 저장한다([기능명세서](video-editing-functional-spec.md) 공통 개념에서 확정).
- 도메인 계층과 영속 계층을 분리한다. 이 문서의 순수 타입이 도메인의 기준이며, 타입별 저장 전용 `@Model` 레코드(예: `ClipRecord`)와 둘 사이의 변환은 영속 계층에 둔다. 도메인은 저장소를 `ProjectRepository` 프로토콜로만 알고, SwiftData 구현은 [프로젝트 저장/불러오기](use-cases/project-management.md)(#7)에서 만든다.
- 영속 계층 구현 시 유의: SwiftData 관계 배열은 순서를 보장하지 않으므로 정렬 인덱스를 별도로 저장하고, `CMTime`은 `value`/`timescale`로 분해해 저장하며, 도메인과 레코드는 같은 `id`를 공유한다.
- Xcode 템플릿의 SwiftData `Item` 모델은 도메인과 무관한 스캐폴딩이다. 메인 윈도우 레이아웃 뼈대(#12)에서 템플릿 `ContentView`를 걷어낼 때 함께 제거한다.

## 이번 범위에서 제외

아래 개념은 해당 기능 이슈에서 이 문서에 추가한다.

- 자막([자막 삽입](use-cases/subtitles.md))
- 트랜지션([트랜지션](use-cases/transitions.md))
- 오버레이·마스크([오버레이 및 마스킹](use-cases/overlays.md))
- 마커([클립 이어붙이기](use-cases/joining-clips.md))
- 폴더·레이블·태그·별점, 프록시([미디어 가져오기](use-cases/media-import.md))
- 재생 속도·역재생([클립 자르기(트림)](use-cases/trimming.md))

## 미정 사항

- `MediaAsset`이 원본 위치를 `URL`로만 들고 있을지, security-scoped bookmark 데이터까지 들고 있을지([파일 접근 권한](file-access-and-sandboxing.md) 참고)
- 트랙 안의 클립 배열을 항상 `timelineStart` 순으로 정렬된 상태로 유지할지, 조회할 때 정렬할지
