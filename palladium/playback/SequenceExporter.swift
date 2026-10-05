import AVFoundation
import OSLog

/// 시퀀스 합성을 동영상 파일(MP4, H.264)로 내보낸다. 미리보기와 같은 합성(`SequenceComposition`)을 써서 결과물이 미리보기와 같다.
nonisolated enum SequenceExporter {
    enum ExportError: Error, LocalizedError {
        case cannotCreateSession

        var errorDescription: String? {
            "내보내기를 시작할 수 없습니다."
        }
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
