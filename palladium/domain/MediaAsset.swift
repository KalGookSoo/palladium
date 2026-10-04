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
}

nonisolated enum MediaKind: String {
    case video
    case audio
    case image
}

// MARK: - Queries

nonisolated extension MediaAsset {
    /// 이미지는 길이가 없어 타임라인에 처음 놓을 때 이 길이로 놓는다.
    static let stillImageDuration = CMTime(value: 5, timescale: 1)

    /// 같은 파일을 가리키는지 판단한다. 같은 파일을 두 번 가져오지 않기 위해 쓴다.
    func refers(to url: URL) -> Bool {
        sourceURL.standardizedFileURL == url.standardizedFileURL
    }

    /// 검색어가 비어 있으면 모든 원본이 일치한다.
    func matches(nameQuery query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        return trimmedQuery.isEmpty || name.localizedStandardContains(trimmedQuery)
    }
}

nonisolated extension MediaAsset: Identifiable {}
nonisolated extension MediaAsset: Equatable {}
