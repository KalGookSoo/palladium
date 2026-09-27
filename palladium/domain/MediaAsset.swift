import CoreMedia
import Foundation

nonisolated struct MediaAsset {
    let id: UUID
    var sourceURL: URL
    let kind: MediaKind
    let duration: CMTime
}

nonisolated enum MediaKind {
    case video
    case audio
    case image
}

extension MediaAsset: Identifiable {}
extension MediaAsset: Equatable {}
