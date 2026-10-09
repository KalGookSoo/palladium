import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// 합성·내보내기 테스트용 미디어 파일을 임시 폴더에 만든다.
enum TestMedia {
    static func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(pathExtension)")
    }

    /// 한 가지 색으로 칠한 무음 영상(기본 30fps). 시각은 1/600초 단위로 반올림해, 59.95처럼 정수가 아닌 값을 주면
    /// 아이폰 영상처럼 프레임 간격이 1/60초와 11/600초로 흔들린다.
    /// `rightHalf`가 있으면 오른쪽 절반을 그 색으로 칠한다(크롭 확인용, #85).
    static func makeVideo(
        red: UInt8, green: UInt8, blue: UInt8, seconds: Double, width: Int = 64, height: Int = 36, fps: Double = 30,
        rightHalf: (red: UInt8, green: UInt8, blue: UInt8)? = nil
    ) async throws -> URL {
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

        let frameCount = Int(seconds * fps)
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
                    let color = column >= width / 2 ? rightHalf ?? (red: red, green: green, blue: blue) : (red: red, green: green, blue: blue)
                    base[offset] = color.blue
                    base[offset + 1] = color.green
                    base[offset + 2] = color.red
                    base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue((Double(frame) * 600 / fps).rounded()), timescale: 600))
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

    /// 단색 PNG 이미지.
    static func makeImage(red: UInt8, green: UInt8, blue: UInt8, width: Int = 100, height: Int = 100) throws -> URL {
        let url = temporaryURL(extension: "png")
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    /// 왼쪽 절반은 빨강, 오른쪽 절반은 파랑인 PNG 이미지(16:9).
    static func makeSplitImage(width: Int = 1920, height: Int = 1080) throws -> URL {
        let url = temporaryURL(extension: "png")
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    /// 이미지의 (가로 비율, 세로 비율) 위치(왼쪽 위 원점) 픽셀의 RGB.
    static func color(of image: CGImage, atX x: Double, y: Double) -> (red: Int, green: Int, blue: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let point = CGRect(x: Int(Double(image.width) * x), y: Int(Double(image.height) * y), width: 1, height: 1)
        let crop = image.cropping(to: point) ?? image
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
