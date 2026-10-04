import CoreMedia
import Foundation

nonisolated struct MediaAsset {
    let id: UUID
    var name: String
    var sourceURL: URL
    let kind: MediaKind
    let duration: CMTime
}

nonisolated enum MediaKind: String {
    case video
    case audio
    case image
}

// MARK: - Queries

extension MediaAsset {
    /// 검색어가 비어 있으면 모든 원본이 일치한다.
    func matches(nameQuery query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        return trimmedQuery.isEmpty || name.localizedStandardContains(trimmedQuery)
    }
}

nonisolated extension MediaAsset: Identifiable {}
nonisolated extension MediaAsset: Equatable {}
