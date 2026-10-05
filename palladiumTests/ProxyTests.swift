import AVFoundation
import CoreGraphics
import Foundation
@testable import palladium
import Testing

struct ProxyTests {
    @Test("프록시 기준은 짧은 변으로 비교해 세로 영상도 같이 판단하고, 끄면 만들지 않는다")
    func thresholdUsesShortSide() {
        #expect(ProxyThreshold.uhd.shouldGenerateProxy(pixelSize: CGSize(width: 3840, height: 2160)))
        #expect(ProxyThreshold.uhd.shouldGenerateProxy(pixelSize: CGSize(width: 2160, height: 3840)))
        #expect(!ProxyThreshold.uhd.shouldGenerateProxy(pixelSize: CGSize(width: 2560, height: 1440)))
        #expect(ProxyThreshold.qhd.shouldGenerateProxy(pixelSize: CGSize(width: 2560, height: 1440)))
        #expect(!ProxyThreshold.qhd.shouldGenerateProxy(pixelSize: CGSize(width: 1920, height: 1080)))
        #expect(!ProxyThreshold.off.shouldGenerateProxy(pixelSize: CGSize(width: 7680, height: 4320)))
        #expect(ProxyThreshold.defaultValue == .uhd)
    }

    @Test("프록시는 원본과 길이가 같고 1080p를 넘지 않는 영상이다")
    func makesProxyWithSameDuration() async throws {
        let sourceURL = try await TestMedia.makeVideo(red: 0, green: 255, blue: 0, seconds: 1, width: 640, height: 360)
        let destination = TestMedia.temporaryURL(extension: "mov")

        try await ProxyGenerator.makeProxy(from: sourceURL, to: destination) { _ in }

        let proxy = AVURLAsset(url: destination)
        let source = AVURLAsset(url: sourceURL)
        let proxyDuration = try await proxy.load(.duration).seconds
        let sourceDuration = try await source.load(.duration).seconds
        #expect(abs(proxyDuration - sourceDuration) < 0.05)
        let track = try #require(try await proxy.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width <= 1920 && size.height <= 1080)
        // 다 쓴 뒤 옮기므로 임시 파일이 남지 않는다.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".partial.mov") }
        #expect(leftovers.isEmpty)
    }
}
