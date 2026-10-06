import CoreMedia
import Foundation

nonisolated struct MediaAsset {
    let id: UUID
    var name: String
    var sourceURL: URL
    let kind: MediaKind
    let duration: CMTime
    /// 앱을 다시 켠 뒤에도 샌드박스 밖의 원본을 열기 위한 security-scoped bookmark. 샘플처럼 북마크 없이 만든 원본은 `nil`이다.
    var bookmarkData: Data? = nil
    /// Finder처럼 원본을 색으로 구분한다. 없으면 `nil`.
    var colorLabel: ColorLabel? = nil
    /// "인터뷰", "B컷"처럼 자유롭게 붙이는 분류어. 검색에 쓰인다.
    var tags: [String] = []
    /// 파생 항목이 쓰는 구간(#81, 트림). 타임라인에 놓으면 이 구간만 클립이 된다. `nil`이면 원본 전체다. 원본 항목·파일에는 두지 않는다.
    var usedRange: CMTimeRange? = nil
    /// 파생 항목(트림 시트의 "새 항목으로 저장"·"자르기"로 만든 항목)이면 처음 원본의 `mediaKey`. 썸네일·파형·프록시를 같은 파일끼리 같이 쓰는 데 쓴다.
    var sourceAssetID: UUID? = nil
}

nonisolated enum MediaKind: String {
    case video
    case audio
    case image
}

/// Finder 태그와 같은 일곱 가지 색.
nonisolated enum ColorLabel: String, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray
}

// MARK: - Queries

nonisolated extension MediaAsset {
    /// 이미지는 길이가 없어 타임라인에 처음 놓을 때 이 길이로 놓는다.
    static let stillImageDuration = CMTime(value: 5, timescale: 1)

    /// 썸네일·파형·프록시 캐시 키. 같은 파일을 가리키는 파생 항목은 처음 원본과 같은 키를 써 다시 만들지 않는다.
    var mediaKey: UUID {
        sourceAssetID ?? id
    }

    /// 트림 시트를 열 수 있는지. 이미지는 길이만 있어 트림하지 않는다.
    var isTrimmable: Bool {
        kind != .image
    }

    /// 원본에서 트림해 만든 파생 항목인지. 원본 항목은 트림으로 바뀌지 않는다.
    var isDerived: Bool {
        sourceAssetID != nil
    }

    /// 같은 파일을 가리키는지 판단한다. 같은 파일을 두 번 가져오지 않기 위해 쓴다.
    func refers(to url: URL) -> Bool {
        sourceURL.standardizedFileURL == url.standardizedFileURL
    }
}

// MARK: - Commands

nonisolated extension MediaAsset {
    /// 포토샵 레이어 이름처럼 프로젝트 안에서만 쓰는 이름으로 바꾼다(원본 파일 이름은 그대로).
    /// 앞뒤 공백을 빼고, 비어 있으면 바꾸지 않는다.
    mutating func rename(to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            name = trimmedName
        }
    }

    /// 쉼표로 나눈 태그 목록으로 바꾼다. 앞뒤 공백과 빈 태그, 중복(대소문자 무시)은 뺀다.
    mutating func setTags(from text: String) {
        var uniqueTags: [String] = []
        for tag in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !tag.isEmpty {
            if !uniqueTags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) {
                uniqueTags.append(tag)
            }
        }
        tags = uniqueTags
    }
}

nonisolated extension MediaAsset: Identifiable {}
nonisolated extension MediaAsset: Equatable {}
