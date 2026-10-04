import AVFoundation
import OSLog

/// 타임라인 클립에 그릴 필름스트립 프레임과 오디오 파형을 만든다. 프로젝트에 저장하지 않고 앱이 켜져 있는 동안 메모리에만 둔다.
final class ClipContentProvider {
    static let shared = ClipContentProvider()
    /// 필름스트립 프레임의 높이(픽셀). 클립 높이를 레티나에서도 선명하게 채운다.
    static let framePixelHeight = 96

    private var frameCache: [String: CGImage] = [:]
    private var peakCache: [MediaAsset.ID: [Float]] = [:]

    /// 프레임을 만들지 못한 칸은 `nil`이다. 이미지 원본은 모든 칸에 같은 축소본을 쓴다.
    func frames(for asset: MediaAsset, at times: [CMTime]) async -> [CGImage?] {
        if asset.kind == .image {
            let image = await MediaThumbnailProvider.shared.thumbnail(for: asset)
            return times.map { _ in image }
        }
        guard asset.kind == .video else { return times.map { _ in nil } }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: MediaFileAccess.resolvedURL(for: asset)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.framePixelHeight * 2, height: Self.framePixelHeight)
        // 칸마다 정확한 프레임일 필요는 없어 가까운 키프레임을 허용해 빠르게 만든다.
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 4)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 4)

        var images: [CGImage?] = []
        for time in times {
            // 30분의 1초 단위로 묶어 줌을 조금 바꿔도 다시 만들지 않는다.
            let key = "\(asset.id)-\(Int(time.seconds * 30))"
            if let cached = frameCache[key] {
                images.append(cached)
                continue
            }
            let image = try? await generator.image(at: time).image
            frameCache[key] = image
            images.append(image)
        }
        return images
    }

    /// 원본 전체의 파형(초당 `ClipContentLayout.peaksPerSecond`개, 0~1). 오디오가 없거나 읽지 못하면 빈 배열.
    func peaks(for asset: MediaAsset) async -> [Float] {
        if let cached = peakCache[asset.id] {
            return cached
        }
        let url = MediaFileAccess.resolvedURL(for: asset)
        let peaks = await Task.detached(priority: .utility) { Self.readPeaks(from: url) }.value
        peakCache[asset.id] = peaks
        return peaks
    }

    /// 모노 8kHz 16비트로 읽어 묶음마다 가장 큰 값을 남긴다.
    private nonisolated static func readPeaks(from url: URL) -> [Float] {
        let sampleRate = 8000.0
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }

        let samplesPerPeak = Int(sampleRate / ClipContentLayout.peaksPerSecond)
        var peaks: [Float] = []
        var currentPeak: Float = 0
        var countInPeak = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            for sample in data {
                currentPeak = max(currentPeak, abs(Float(sample)) / Float(Int16.max))
                countInPeak += 1
                if countInPeak == samplesPerPeak {
                    peaks.append(currentPeak)
                    currentPeak = 0
                    countInPeak = 0
                }
            }
        }
        if countInPeak > 0 {
            peaks.append(currentPeak)
        }
        if reader.status == .failed {
            Logger.mediaImport.notice("파형을 읽지 못함: \(url.lastPathComponent, privacy: .public)")
        }
        return peaks
    }
}
