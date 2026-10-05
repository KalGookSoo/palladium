import AVFoundation
import OSLog

/// 시퀀스를 재생·내보내기에 함께 쓰는 AVFoundation 합성으로 만든 결과. 미리보기와 결과물이 같은 합성을 쓰게 하기 위함이다.
nonisolated struct SequenceComposition {
    let asset: AVComposition
    /// 영상 트랙이 없으면(소리만 있으면) `nil`.
    let videoComposition: AVVideoComposition?
    let duration: CMTime
}

/// 1단계(#5): 메인 영상 트랙(맨 아래 영상 트랙)과 그 소리, 오디오 트랙들을 합성한다.
/// 위쪽 영상 트랙(오버레이)과 이미지 클립은 2단계(#9와 함께)에서 그린다. 그전까지 메인 트랙의 이미지 자리는 검은 화면이다.
nonisolated enum SequenceComposer {
    static let frameDuration = CMTime(value: 1, timescale: 30)
    /// 화면비 프리셋의 짧은 변(픽셀).
    static let renderShortSide = 1080.0

    // MARK: - Queries

    static func renderSize(for preset: AspectRatioPreset) -> CGSize {
        let width = Double(preset.widthRatio)
        let height = Double(preset.heightRatio)
        let scale = renderShortSide / min(width, height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    /// 원본 영상(회전 정보 포함)을 화면 안에 비율을 지켜 가운데 맞춘다. 남는 곳은 검은 띠가 된다.
    static func fitTransform(naturalSize: CGSize, preferredTransform: CGAffineTransform, into renderSize: CGSize) -> CGAffineTransform {
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard displayed.width > 0, displayed.height > 0 else { return preferredTransform }
        let scale = min(renderSize.width / displayed.width, renderSize.height / displayed.height)
        let normalized = preferredTransform.concatenating(CGAffineTransform(translationX: -displayed.minX, y: -displayed.minY))
        let offset = CGPoint(
            x: (renderSize.width - displayed.width * scale) / 2,
            y: (renderSize.height - displayed.height * scale) / 2
        )
        return normalized
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
    }

    // MARK: - Composition

    /// 클립이 하나도 없으면 `nil`. 원본을 읽지 못한 클립은 건너뛰고(그 자리는 비어 있음) 나머지로 합성한다.
    static func makeComposition(
        sequence: EditSequence,
        assets: [MediaAsset],
        aspectRatio: AspectRatioPreset,
        resolveURL: (MediaAsset) -> URL
    ) async -> SequenceComposition? {
        guard sequence.duration > .zero else { return nil }
        let composition = AVMutableComposition()
        let renderSize = renderSize(for: aspectRatio)
        var videoSegments: [(range: CMTimeRange, transform: CGAffineTransform)] = []

        // 메인 영상 트랙: 화면 아래쪽(배열 뒤쪽)의 영상 트랙이 메인이다.
        if let mainTrack = sequence.tracks.last(where: { $0.kind == .video }) {
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            for clip in mainTrack.clips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                guard let asset = assets.first(where: { $0.id == clip.assetID }), asset.kind == .video else { continue }
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceVideo = try await source.loadTracks(withMediaType: .video).first, let videoTrack {
                        try videoTrack.insertTimeRange(clip.sourceRange, of: sourceVideo, at: clip.timelineStart)
                        let (naturalSize, preferredTransform) = try await sourceVideo.load(.naturalSize, .preferredTransform)
                        videoSegments.append((
                            clip.timelineRange,
                            fitTransform(naturalSize: naturalSize, preferredTransform: preferredTransform, into: renderSize)
                        ))
                    }
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let soundTrack {
                        try soundTrack.insertTimeRange(clip.sourceRange, of: sourceAudio, at: clip.timelineStart)
                    }
                } catch {
                    Logger.playback.error("합성에서 클립을 건너뜀: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // 오디오 트랙: 트랙마다 합성 오디오 트랙 하나.
        for track in sequence.tracks where track.kind == .audio {
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            for clip in track.clips {
                guard let asset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                // 원본 에셋을 변수로 붙잡아 둬야 한다. 임시로 만든 에셋이 사라지면 그 트랙을 합성에 넣지 못한다.
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let audioTrack {
                        try audioTrack.insertTimeRange(clip.sourceRange, of: sourceAudio, at: clip.timelineStart)
                    }
                } catch {
                    Logger.playback.error("합성에서 클립을 건너뜀: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // 아무것도 넣지 못한 트랙은 지운다.
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }
        // 클립이 있어도 재생 길이는 시퀀스 길이로 맞춘다(뒤쪽 빈 시간·이미지 자리도 재생되게).
        let duration = sequence.duration
        guard let videoTrack = composition.tracks(withMediaType: .video).first else {
            return SequenceComposition(asset: composition, videoComposition: nil, duration: duration)
        }
        return SequenceComposition(
            asset: composition,
            videoComposition: makeVideoComposition(track: videoTrack, segments: videoSegments, duration: duration, renderSize: renderSize),
            duration: duration
        )
    }

    /// 클립 구간마다 맞춤 변환을, 빈 구간에는 검은 화면을 그리는 지시를 처음부터 끝까지 빈틈없이 만든다.
    private static func makeVideoComposition(
        track: AVCompositionTrack,
        segments: [(range: CMTimeRange, transform: CGAffineTransform)],
        duration: CMTime,
        renderSize: CGSize
    ) -> AVVideoComposition {
        var instructions: [AVVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        func appendInstruction(_ range: CMTimeRange, transform: CGAffineTransform?) {
            guard range.duration > .zero else { return }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            if let transform {
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                layer.setTransform(transform, at: range.start)
                instruction.layerInstructions = [layer]
            }
            instructions.append(instruction)
        }
        for segment in segments.sorted(by: { $0.range.start < $1.range.start }) {
            appendInstruction(CMTimeRange(start: cursor, end: segment.range.start), transform: nil)
            appendInstruction(segment.range, transform: segment.transform)
            cursor = segment.range.end
        }
        appendInstruction(CMTimeRange(start: cursor, end: duration), transform: nil)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions
        return videoComposition
    }
}
