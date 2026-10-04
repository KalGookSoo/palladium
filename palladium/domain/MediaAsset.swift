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
    /// 0(별점 없음)부터 `maximumRating`까지.
    var rating: Int = 0
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

    /// 같은 파일을 가리키는지 판단한다. 같은 파일을 두 번 가져오지 않기 위해 쓴다.
    func refers(to url: URL) -> Bool {
        sourceURL.standardizedFileURL == url.standardizedFileURL
    }

    static let maximumRating = 5
}

// MARK: - Commands

nonisolated extension MediaAsset {
    /// 범위를 벗어난 별점은 가장 가까운 값으로 맞춘다.
    mutating func rate(_ stars: Int) {
        rating = min(max(stars, 0), Self.maximumRating)
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
