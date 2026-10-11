import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 둘러보기(#63)에 쓸 샘플 미디어를 기기에서 직접 만든다. 앱에 넣지 않아 앱 크기·저작권·네트워크 걱정이 없다.
/// 색 배경 위로 움직이는 도형과 글자가 있는 영상 3개(가로 2·세로 1), 로고 PNG, 단순 화음 배경음악을 만든다.
/// 이미 만든 파일이 있으면 다시 만들지 않는다.
nonisolated enum SampleMediaGenerator {
    struct VideoSpec {
        let fileName: String
        let title: String
        let width: Int
        let height: Int
        let seconds: Double
        /// 배경색(RGB 0~1).
        let background: (Double, Double, Double)
    }

    static let videos = [
        VideoSpec(fileName: "바다.mov", title: "바다", width: 1280, height: 720, seconds: 6, background: (0.10, 0.40, 0.70)),
        VideoSpec(fileName: "도시.mov", title: "도시", width: 1280, height: 720, seconds: 6, background: (0.55, 0.25, 0.45)),
        VideoSpec(fileName: "세로 영상.mov", title: "세로", width: 720, height: 1280, seconds: 5, background: (0.15, 0.50, 0.30)),
    ]
    static let logoFileName = "로고.png"
    static let musicFileName = "배경음악.m4a"
    static let musicSeconds = 16.0
    private static let fps = 30

    /// 샘플을 둘 앱 폴더(Application Support/palladium/Samples). 샌드박스 컨테이너 안이라 따로 권한이 필요 없다.
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "palladium/Samples", directoryHint: .isDirectory)
    }

    /// 모든 샘플 파일을 `directory`에 만들고(있으면 그대로 두고) 가져올 순서대로 돌려준다: 영상들, 로고, 배경음악.
    static func makeAll(in directory: URL = defaultDirectory) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for spec in videos {
            let url = directory.appending(path: spec.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                try await makeVideo(spec, to: url)
            }
            urls.append(url)
        }
        let logo = directory.appending(path: logoFileName)
        if !FileManager.default.fileExists(atPath: logo.path) {
            try makeLogo(to: logo)
        }
        urls.append(logo)
        let music = directory.appending(path: musicFileName)
        if !FileManager.default.fileExists(atPath: music.path) {
            try makeMusic(to: music)
        }
        urls.append(music)
        return urls
    }

    // MARK: - Video

    enum GenerationError: Error {
        case cannotWrite(String)
    }

    /// 배경과 제목 글자는 한 번만 그려 두고, 프레임마다 그 위에 움직이는 원과 시각 글자를 그린다.
    static func makeVideo(_ spec: VideoSpec, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: spec.width,
            AVVideoHeightKey: spec.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: spec.width,
            kCVPixelBufferHeightKey as String: spec.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw GenerationError.cannotWrite(spec.fileName) }
        writer.startSession(atSourceTime: .zero)

        let background = makeBackground(spec)
        let frameCount = Int(spec.seconds * Double(fps))
        for frame in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw GenerationError.cannotWrite(spec.fileName) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            drawFrame(frame, of: spec, background: background, into: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? GenerationError.cannotWrite(spec.fileName)
        }
    }

    private static func makeBackground(_ spec: VideoSpec) -> CGImage? {
        guard let context = bitmapContext(width: spec.width, height: spec.height) else { return nil }
        let (red, green, blue) = spec.background
        let colors = [CGColor(red: red, green: green, blue: blue, alpha: 1), CGColor(red: red * 0.5, green: green * 0.5, blue: blue * 0.5, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: spec.height), end: CGPoint(x: spec.width, y: 0), options: [])
        }
        let size = Double(min(spec.width, spec.height)) * 0.18
        drawText(spec.title, in: context, size: size, center: CGPoint(x: Double(spec.width) / 2, y: Double(spec.height) * 0.62), alpha: 0.95)
        drawText("palladium 샘플", in: context, size: size * 0.3, center: CGPoint(x: Double(spec.width) / 2, y: Double(spec.height) * 0.62 - size * 0.8), alpha: 0.7)
        return context.makeImage()
    }

    private static func drawFrame(_ frame: Int, of spec: VideoSpec, background: CGImage?, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: spec.width,
            height: spec.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        let bounds = CGRect(x: 0, y: 0, width: spec.width, height: spec.height)
        if let background {
            context.draw(background, in: bounds)
        }
        // 화면을 가로지르며 위아래로 출렁이는 원. 얼굴처럼 가릴 대상을 연습하는 데도 쓴다.
        let progress = Double(frame) / (spec.seconds * Double(fps))
        let radius = Double(min(spec.width, spec.height)) * 0.08
        let x = radius + (Double(spec.width) - radius * 2) * progress
        let y = Double(spec.height) * 0.3 + sin(progress * .pi * 4) * Double(spec.height) * 0.08
        context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        let seconds = Double(frame) / Double(fps)
        let label = String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
        drawText(label, in: context, size: Double(min(spec.width, spec.height)) * 0.05, center: CGPoint(x: Double(spec.width) - 90, y: 40), alpha: 0.85)
    }

    // MARK: - Logo

    /// 투명 배경 위 둥근 사각형 로고(오버레이 연습용).
    static func makeLogo(to url: URL) throws {
        let side = 600
        guard let context = bitmapContext(width: side, height: side) else { throw GenerationError.cannotWrite(logoFileName) }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        let box = CGRect(x: 40, y: 40, width: side - 80, height: side - 80)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 120, cornerHeight: 120, transform: nil))
        context.setFillColor(CGColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1))
        context.fillPath()
        drawText("LOGO", in: context, size: 150, center: CGPoint(x: Double(side) / 2, y: Double(side) / 2), alpha: 1)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GenerationError.cannotWrite(logoFileName) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationError.cannotWrite(logoFileName) }
    }

    // MARK: - Music

    /// 도-미-솔(C 장조) 화음을 2초마다 바꿔 가며(C·Am·F·G) 부드럽게 울리는 배경음악(AAC 스테레오).
    static func makeMusic(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let sampleRate = 44100.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(sampleRate * musicSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount), let channels = buffer.floatChannelData else {
            throw GenerationError.cannotWrite(musicFileName)
        }
        buffer.frameLength = frameCount
        // C·Am·F·G 화음(Hz).
        let chords: [[Float]] = [[261.63, 329.63, 392.00], [220.00, 261.63, 329.63], [174.61, 220.00, 261.63], [196.00, 246.94, 293.66]]
        let chordSeconds: Float = 2
        for index in 0 ..< Int(frameCount) {
            let time = Float(index) / Float(sampleRate)
            let chord = chords[Int(time / chordSeconds) % chords.count]
            let local = time.truncatingRemainder(dividingBy: chordSeconds)
            // 화음마다 살짝 올라왔다 줄어드는 음량.
            let envelope = min(local / 0.15, 1) * (1 - 0.5 * local / chordSeconds)
            let fade = min(time / 1, 1) * min((Float(musicSeconds) - time) / 1, 1)
            let sample = chord.reduce(0) { $0 + sin(2 * .pi * $1 * time) } / Float(chord.count) * 0.3 * envelope * fade
            for channel in 0 ..< Int(format.channelCount) {
                channels[channel][index] = sample
            }
        }
        try file.write(from: buffer)
    }

    // MARK: - Helpers

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 흰 글자를 `center`를 가운데로 그린다(CoreGraphics 좌표, 아래가 원점).
    private static func drawText(_ text: String, in context: CGContext, size: Double, center: CGPoint, alpha: Double) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: alpha),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
        CTLineDraw(line, context)
    }
}
