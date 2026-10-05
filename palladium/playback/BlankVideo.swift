import AVFoundation

/// 검은 프레임 하나짜리 1초 영상. 클립이 없는 구간에 자막만 있을 때 합성 길이를 채우는 바탕으로 쓴다(#4).
/// 빈 구간만 있는 영상 트랙은 내보내기가 거부하므로 실제 미디어가 필요하다. 한 번 만들어 임시 폴더에 둔다.
nonisolated enum BlankVideo {
    static let duration = CMTime(value: 1, timescale: 1)
    private static let size = 16

    static func url() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "palladium-blank-v1.mov")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let partial = FileManager.default.temporaryDirectory.appending(path: "palladium-blank-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
        if let buffer {
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: .zero)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
        // 동시에 만든 다른 쪽이 먼저 옮겼으면 그 파일을 쓴다.
        try? FileManager.default.moveItem(at: partial, to: url)
        try? FileManager.default.removeItem(at: partial)
        return url
    }
}
