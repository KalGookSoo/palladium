import AVFoundation
import ImageIO
import OSLog

/// 미디어 패널 행에 보일 원본 썸네일을 만든다. 프로젝트에 저장하지 않고, 앱이 켜져 있는 동안 메모리에만 둔다.
/// 오디오는 썸네일 대신 아이콘을 쓴다(파형은 #31).
final class MediaThumbnailProvider {
    static let shared = MediaThumbnailProvider()
    /// 썸네일의 긴 변(픽셀). 행의 썸네일 칸을 레티나에서도 선명하게 채우는 크기다.
    static let maximumPixelSize = 160

    private var cache: [MediaAsset.ID: CGImage] = [:]

    // MARK: - Queries

    /// 첫 프레임은 검은 화면인 경우가 많아 1초 지점을 쓰고, 1초보다 짧으면 가운데를 쓴다.
    nonisolated static func thumbnailTime(for duration: CMTime) -> CMTime {
        CMTimeMinimum(CMTime(value: 1, timescale: 1), CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2))
    }

    /// 만들 수 없으면(오디오, 파일 없음, 읽기 실패) `nil`.
    func thumbnail(for asset: MediaAsset) async -> CGImage? {
        if let cached = cache[asset.mediaKey] {
            return cached
        }
        let url = MediaFileAccess.resolvedURL(for: asset)
        let image: CGImage? = switch asset.kind {
        case .video: await Self.videoThumbnail(at: url, duration: asset.duration)
        case .image: Self.imageThumbnail(at: url)
        case .audio: nil
        }
        cache[asset.mediaKey] = image
        return image
    }

    // MARK: - Helpers

    private static func videoThumbnail(at url: URL, duration: CMTime) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        do {
            return try await generator.image(at: thumbnailTime(for: duration)).image
        } catch {
            Logger.mediaImport.notice("썸네일을 만들지 못함: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    private static func imageThumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
