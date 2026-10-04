import Foundation
import OSLog

/// 가져온 원본의 북마크로 접근 권한을 다시 얻는다. 한 번 얻은 권한은 앱이 켜져 있는 동안 유지한다.
enum MediaFileAccess {
    private static var accessedURLs: Set<URL> = []

    /// 북마크가 없거나 풀지 못하면 저장된 경로를 그대로 돌려준다.
    static func resolvedURL(for asset: MediaAsset) -> URL {
        guard let bookmarkData = asset.bookmarkData else { return asset.sourceURL }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            if isStale {
                Logger.mediaImport.notice("오래된 북마크: \(asset.name, privacy: .public)")
            }
            if !accessedURLs.contains(url), url.startAccessingSecurityScopedResource() {
                accessedURLs.insert(url)
            }
            return url
        } catch {
            Logger.mediaImport.error("북마크 풀기 실패: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
            return asset.sourceURL
        }
    }
}
