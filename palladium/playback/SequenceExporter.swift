import AVFoundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// 시퀀스 합성을 동영상 파일(MP4, H.264)로 내보낸다. 미리보기와 같은 합성(`SequenceComposition`)을 써서 결과물이 미리보기와 같다.
nonisolated enum SequenceExporter {
    enum ExportError: Error, LocalizedError {
        case cannotCreateSession
        case noPicture
        case cannotWriteImage

        var errorDescription: String? {
            switch self {
            case .cannotCreateSession: "내보내기를 시작할 수 없습니다."
            case .noPicture: "이 시각에는 화면에 그릴 영상·이미지가 없습니다."
            case .cannotWriteImage: "이미지 파일을 쓸 수 없습니다."
            }
        }
    }

    /// `time`의 프레임을 합성 화면 크기 그대로 PNG로 저장한다(#6 2단계). 미리보기와 같은 합성이라 보이던 프레임과 같다.
    static func exportStillFrame(_ composition: SequenceComposition, at time: CMTime, to url: URL) async throws {
        guard let videoComposition = composition.videoComposition else { throw ExportError.noPicture }
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // 끝 시각에는 프레임이 없으므로 마지막 프레임으로 맞춘다.
        let lastFrame = CMTimeMaximum(composition.duration - composition.frameDuration, .zero)
        let image = try await generator.image(at: CMTimeMinimum(CMTimeMaximum(time, .zero), lastFrame)).image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.cannotWriteImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.cannotWriteImage }
        Logger.export.notice("정지 프레임 저장: \(url.lastPathComponent, privacy: .public)")
    }

    /// `progress`는 0~1로 여러 번 불린다. 같은 경로에 파일이 있으면 덮어쓴다. 실패하거나 취소되면 만들던 파일을 지운다.
    /// 해상도·프레임레이트는 합성(`composition`)이 정하고, 코덱과 화질(비트레이트, #77)은 여기서 정한다.
    /// 프리셋(`AVAssetExportSession`)은 비트레이트를 마음대로 정해 원본보다 낮게 나올 수 있어, 합성을 직접 읽어(`AVAssetReader`)
    /// 정한 비트레이트로 인코딩한다(`AVAssetWriter`). 영상은 H.264/HEVC, 소리는 AAC 48kHz 스테레오다.
    static func export(
        _ composition: SequenceComposition,
        to url: URL,
        codec: ExportCodec = .defaultValue,
        quality: ExportQuality = .defaultValue,
        customMbps: Double = ExportBitRate.defaultCustomMbps,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        do {
            let job = try await EncodingJob(composition: composition, url: url, codec: codec, quality: quality, customMbps: customMbps, progress: progress)
            try await withTaskCancellationHandler {
                try await job.run()
            } onCancel: {
                job.cancel()
            }
            try Task.checkCancellation()
            progress(1)
            Logger.export.notice("내보내기 완료: \(url.lastPathComponent, privacy: .public)")
        } catch {
            try? FileManager.default.removeItem(at: url)
            Logger.export.error("내보내기 실패: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// 영상 비트레이트(초당 비트). 테스트와 화면 안내가 같은 값을 쓰게 한다.
    static func videoBitRate(for composition: SequenceComposition, codec: ExportCodec, quality: ExportQuality, customMbps: Double) -> Double? {
        guard let videoComposition = composition.videoComposition else { return nil }
        return ExportBitRate.bitsPerSecond(
            quality: quality,
            codec: codec,
            renderSize: videoComposition.renderSize,
            frameDuration: composition.frameDuration,
            sourceBitRate: composition.sourceBitRate,
            customMbps: customMbps
        )
    }
}

/// 합성을 읽어 파일로 쓰는 작업 하나. 영상·소리 입력이 각자의 큐에서 준비되는 대로 샘플을 넘긴다.
/// 취소하면 읽기·쓰기를 멈추고 오류(`CancellationError`)로 끝난다.
private final nonisolated class EncodingJob: @unchecked Sendable {
    private struct Pipe {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        let isVideo: Bool
    }

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pipes: [Pipe]
    private let duration: CMTime
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var isCancelled = false
    private var failure: Error?

    init(
        composition: SequenceComposition, url: URL, codec: ExportCodec, quality: ExportQuality, customMbps: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        reader = try AVAssetReader(asset: composition.asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        duration = composition.duration
        self.progress = progress
        var pipes: [Pipe] = []

        let videoTracks = try await composition.asset.loadTracks(withMediaType: .video)
        if let videoComposition = composition.videoComposition, !videoTracks.isEmpty,
           let bitRate = SequenceExporter.videoBitRate(for: composition, codec: codec, quality: quality, customMbps: customMbps)
        {
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: videoTracks,
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.videoComposition = videoComposition
            output.alwaysCopiesSampleData = false
            let fps = 1 / composition.frameDuration.seconds
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int((fps * 2).rounded()),
            ]
            if codec == .h264 {
                compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoComposition.renderSize.width),
                AVVideoHeightKey: Int(videoComposition.renderSize.height),
                AVVideoCompressionPropertiesKey: compression,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
            input.expectsMediaDataInRealTime = false
            pipes.append(Pipe(output: output, input: input, isVideo: true))
        }

        let audioTracks = try await composition.asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            output.audioMix = composition.audioMix
            // 재생 속도를 바꾼 클립의 소리가 높낮이를 지키게 한다(#58, 미리보기와 같음).
            output.audioTimePitchAlgorithm = .spectral
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000,
            ])
            input.expectsMediaDataInRealTime = false
            pipes.append(Pipe(output: output, input: input, isVideo: false))
        }

        guard !pipes.isEmpty else { throw SequenceExporter.ExportError.cannotCreateSession }
        for pipe in pipes {
            guard reader.canAdd(pipe.output), writer.canAdd(pipe.input) else { throw SequenceExporter.ExportError.cannotCreateSession }
            reader.add(pipe.output)
            writer.add(pipe.input)
        }
        self.pipes = pipes
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }

    private var shouldStop: Bool {
        lock.withLock { isCancelled || failure != nil }
    }

    func run() async throws {
        guard reader.startReading() else { throw reader.error ?? SequenceExporter.ExportError.cannotCreateSession }
        guard writer.startWriting() else { throw writer.error ?? SequenceExporter.ExportError.cannotCreateSession }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            for pipe in pipes {
                group.addTask { await self.pump(pipe) }
            }
        }

        if lock.withLock({ isCancelled }) {
            reader.cancelReading()
            writer.cancelWriting()
            throw CancellationError()
        }
        if let failure = lock.withLock({ failure }) ?? (reader.status == .failed ? reader.error : nil) {
            reader.cancelReading()
            writer.cancelWriting()
            throw failure
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? SequenceExporter.ExportError.cannotCreateSession
        }
    }

    /// 입력이 받을 수 있을 때마다 샘플을 넘기고, 다 넘기거나 멈추면 입력을 닫는다.
    private func pump(_ pipe: Pipe) async {
        let queue = DispatchQueue(label: "palladium.export.\(pipe.isVideo ? "video" : "audio")")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            pipe.input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while pipe.input.isReadyForMoreMediaData {
                    if shouldStop {
                        finished = true
                        pipe.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard let sample = pipe.output.copyNextSampleBuffer() else {
                        finished = true
                        pipe.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if !pipe.input.append(sample) {
                        lock.withLock { failure = failure ?? writer.error ?? SequenceExporter.ExportError.cannotCreateSession }
                        finished = true
                        pipe.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if pipe.isVideo || pipes.count == 1 {
                        let time = CMSampleBufferGetPresentationTimeStamp(sample)
                        if time.isNumeric, duration.seconds > 0 {
                            progress(min(max(time.seconds / duration.seconds, 0), 0.99))
                        }
                    }
                }
            }
        }
    }
}
