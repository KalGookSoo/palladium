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
        let lastFrame = CMTimeMaximum(composition.duration - SequenceComposer.frameDuration, .zero)
        let image = try await generator.image(at: CMTimeMinimum(CMTimeMaximum(time, .zero), lastFrame)).image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.cannotWriteImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.cannotWriteImage }
        Logger.export.notice("정지 프레임 저장: \(url.lastPathComponent, privacy: .public)")
    }

    /// `progress`는 0~1로 여러 번 불린다. 같은 경로에 파일이 있으면 덮어쓴다. 실패하거나 취소되면 만들던 파일을 지운다.
    static func export(
        _ composition: SequenceComposition,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let session = AVAssetExportSession(asset: composition.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotCreateSession
        }
        session.videoComposition = composition.videoComposition
        session.audioMix = composition.audioMix
        session.audioTimePitchAlgorithm = .spectral
        session.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        try? FileManager.default.removeItem(at: url)

        let progressTask = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case let .exporting(exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }
        do {
            try await session.export(to: url, as: .mp4)
            progress(1)
            Logger.export.notice("내보내기 완료: \(url.lastPathComponent, privacy: .public)")
        } catch {
            try? FileManager.default.removeItem(at: url)
            Logger.export.error("내보내기 실패: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
