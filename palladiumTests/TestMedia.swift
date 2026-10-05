import AVFoundation
import CoreGraphics
import Foundation

/// 합성·내보내기 테스트용 미디어 파일을 임시 폴더에 만든다.
enum TestMedia {
    static func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(pathExtension)")
    }

    /// 한 가지 색으로 칠한 무음 영상(30fps).
    static func makeVideo(red: UInt8, green: UInt8, blue: UInt8, seconds: Double, width: Int = 64, height: Int = 36) async throws -> URL {
        let url = temporaryURL(extension: "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(seconds * 30)
        for frame in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let offset = row * bytesPerRow + column * 4
                    base[offset] = blue
                    base[offset + 1] = green
                    base[offset + 2] = red
                    base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// 440Hz 사인파 오디오.
    static func makeTone(seconds: Double) throws -> URL {
        let url = temporaryURL(extension: "wav")
        let sampleRate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for index in 0 ..< Int(frameCount) {
            buffer.floatChannelData?[0][index] = 0.5 * sin(Float(index) * 2 * .pi * 440 / Float(sampleRate))
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }

    /// 이미지 가운데 픽셀의 RGB.
    static func centerColor(of image: CGImage) -> (red: Int, green: Int, blue: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let crop = image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)) ?? image
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
