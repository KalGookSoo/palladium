import CoreMedia
import Foundation
import ImageIO
@testable import palladium
import Testing
import UniformTypeIdentifiers

@MainActor
struct MediaThumbnailProviderTests {
    @Test("영상 썸네일은 1초 지점을 쓰고, 1초보다 짧으면 가운데를 쓴다")
    func thumbnailTimeSkipsFirstFrame() {
        #expect(MediaThumbnailProvider.thumbnailTime(for: CMTime(value: 10, timescale: 1)).seconds == 1)
        #expect(MediaThumbnailProvider.thumbnailTime(for: CMTime(value: 1, timescale: 2)).seconds == 0.25)
    }

    @Test("이미지 썸네일은 긴 변이 정해진 크기를 넘지 않는다")
    func imageThumbnailIsDownsampled() async throws {
        let url = try makeImage(width: 800, height: 400)
        let asset = MediaAsset(id: UUID(), name: "wide.png", sourceURL: url, kind: .image, duration: MediaAsset.stillImageDuration)

        let image = try #require(await MediaThumbnailProvider().thumbnail(for: asset))

        #expect(max(image.width, image.height) == MediaThumbnailProvider.maximumPixelSize)
    }

    @Test("오디오와 파일이 없는 원본은 썸네일이 없다")
    func audioAndMissingFilesHaveNoThumbnail() async {
        let provider = MediaThumbnailProvider()
        #expect(await provider.thumbnail(for: SampleData.backgroundMusic) == nil)
        #expect(await provider.thumbnail(for: SampleData.bRollVideo) == nil)
    }

    private func makeImage(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
