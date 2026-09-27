import CoreMedia
import Foundation

/// 프로젝트로 가져온 원본 미디어 파일 하나.
nonisolated struct MediaAsset {
    /// 원본을 구분하는 고유 식별자.
    let id: UUID
    /// 원본 파일의 위치.
    var sourceURL: URL
    /// 원본의 종류
    let kind: MediaKind
    /// 원본의 전체 길이.
    let duration: CMTime
}

nonisolated enum MediaKind {
    case video
    case audio
    case image
}

extension MediaAsset: Identifiable {}
extension MediaAsset: Equatable {}
