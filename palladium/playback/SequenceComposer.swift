import AVFoundation
import CoreImage
import ImageIO
import OSLog

/// 시퀀스를 재생·내보내기에 함께 쓰는 AVFoundation 합성으로 만든 결과. 미리보기와 결과물이 같은 합성을 쓰게 하기 위함이다.
nonisolated struct SequenceComposition {
    let asset: AVComposition
    /// 영상 트랙이 없으면(소리만 있으면) `nil`.
    let videoComposition: AVVideoComposition?
    /// 클립·트랙 음량과 음소거(#44).
    let audioMix: AVAudioMix?
    let duration: CMTime
}

/// 시퀀스의 모든 영상 트랙(아래 트랙이 먼저, 위 트랙이 그 위에)과 이미지 클립을 클립마다의 위치·크기·불투명도로 겹쳐 그리고(#5 2단계, #9),
/// 영상 클립의 소리와 오디오 트랙을 함께 넣는다. 자막은 맨 위에 그린다(#4). 그리기는 `LayerCompositor`가 한다.
nonisolated enum SequenceComposer {
    static let frameDuration = CMTime(value: 1, timescale: 30)
    /// 화면비 프리셋의 짧은 변(픽셀).
    static let renderShortSide = 1080.0
    /// 이미지 층을 불러올 때의 최대 긴 변(픽셀). 화면보다 크게 불러 와도 보이는 차이가 없어 메모리를 아낀다.
    static let maximumImagePixelSize = 2160

    // MARK: - Queries

    static func renderSize(for preset: AspectRatioPreset) -> CGSize {
        let width = Double(preset.widthRatio)
        let height = Double(preset.heightRatio)
        let scale = renderShortSide / min(width, height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
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
        // 층으로 그릴 클립: (타임라인 구간, 층, 쌓는 순서 — 클수록 위).
        var placedLayers: [(range: CMTimeRange, layer: CompositionLayer, order: Int)] = []
        var images: [MediaAsset.ID: CIImage] = [:]
        // 소리 구간마다의 음량: (합성 오디오 트랙, 클립 시작, 음량).
        var volumes: [(trackID: CMPersistentTrackID, start: CMTime, volume: Float)] = []

        for (trackIndex, track) in sequence.tracks.enumerated() where track.kind == .video {
            // 트랙 배열은 화면 위쪽부터라, 앞에 있을수록 위에 그린다.
            let order = sequence.tracks.count - trackIndex
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            for clip in track.clips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                guard let asset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                if asset.kind == .image {
                    if images[asset.id] == nil {
                        images[asset.id] = loadImage(at: resolveURL(asset))
                    }
                    if let image = images[asset.id] {
                        placedLayers.append((clip.timelineRange, CompositionLayer(content: .image(image), transform: clip.transform), order))
                    }
                    continue
                }
                // 원본 에셋을 변수로 붙잡아 둬야 한다. 임시로 만든 에셋이 사라지면 그 트랙을 합성에 넣지 못한다.
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceVideo = try await source.loadTracks(withMediaType: .video).first, let videoTrack {
                        try videoTrack.insertTimeRange(clip.sourceRange, of: sourceVideo, at: clip.timelineStart)
                        let (naturalSize, preferredTransform) = try await sourceVideo.load(.naturalSize, .preferredTransform)
                        let content = CompositionLayer.Content.video(trackID: videoTrack.trackID, naturalSize: naturalSize, preferredTransform: preferredTransform)
                        placedLayers.append((clip.timelineRange, CompositionLayer(content: content, transform: clip.transform), order))
                    }
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let soundTrack {
                        try soundTrack.insertTimeRange(clip.sourceRange, of: sourceAudio, at: clip.timelineStart)
                        volumes.append((soundTrack.trackID, clip.timelineStart, Float(sequence.effectiveVolume(of: clip.id))))
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
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let audioTrack {
                        try audioTrack.insertTimeRange(clip.sourceRange, of: sourceAudio, at: clip.timelineStart)
                        volumes.append((audioTrack.trackID, clip.timelineStart, Float(sequence.effectiveVolume(of: clip.id))))
                    }
                } catch {
                    Logger.playback.error("합성에서 클립을 건너뜀: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // 자막은 모든 트랙 위에 그린다.
        for subtitle in sequence.subtitles {
            placedLayers.append((subtitle.range, CompositionLayer(content: .subtitle(subtitle), transform: ClipTransform()), Int.max))
        }

        // 아무것도 넣지 못한 트랙은 지운다.
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }
        let duration = sequence.duration
        // 자막만 있거나 자막이 클립보다 늦게 끝나면 검은 바탕 영상을 늘여 길이를 채워, 합성기가 그 구간도 그리게 한다.
        if !placedLayers.isEmpty, composition.tracks(withMediaType: .video).isEmpty || composition.duration < duration {
            await addBlankBase(to: composition, duration: duration)
        }
        let audioMix = makeAudioMix(composition: composition, volumes: volumes)
        guard !placedLayers.isEmpty else {
            return SequenceComposition(asset: composition, videoComposition: nil, audioMix: audioMix, duration: duration)
        }
        return SequenceComposition(
            asset: composition,
            videoComposition: makeVideoComposition(layers: placedLayers, duration: duration, renderSize: renderSize(for: aspectRatio)),
            audioMix: audioMix,
            duration: duration
        )
    }

    /// 클립 경계마다 구간을 나누고, 구간마다 그 시각에 걸친 층을 아래부터 쌓는다. 처음부터 끝까지 빈틈없이 덮는다.
    private static func makeVideoComposition(
        layers: [(range: CMTimeRange, layer: CompositionLayer, order: Int)],
        duration: CMTime,
        renderSize: CGSize
    ) -> AVVideoComposition {
        let boundaries = Set([CMTime.zero, duration] + layers.flatMap { [$0.range.start, $0.range.end] })
            .filter { $0 >= .zero && $0 <= duration }
            .sorted()
        let instructions = zip(boundaries, boundaries.dropFirst()).compactMap { start, end -> LayerInstruction? in
            guard start < end else { return nil }
            let active = layers
                .filter { $0.range.start <= start && start < $0.range.end }
                .sorted { $0.order < $1.order }
                .map(\.layer)
            return LayerInstruction(timeRange: CMTimeRange(start: start, end: end), layers: active)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = LayerCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions
        return videoComposition
    }

    /// 합성 오디오 트랙마다 클립이 시작하는 시각에 그 클립의 음량을 둔다(다음 클립 시작까지 유지).
    private static func makeAudioMix(
        composition: AVComposition,
        volumes: [(trackID: CMPersistentTrackID, start: CMTime, volume: Float)]
    ) -> AVAudioMix? {
        let parameters = composition.tracks(withMediaType: .audio).map { track in
            let trackParameters = AVMutableAudioMixInputParameters(track: track)
            for entry in volumes.filter({ $0.trackID == track.trackID }).sorted(by: { $0.start < $1.start }) {
                trackParameters.setVolume(entry.volume, at: entry.start)
            }
            return trackParameters
        }
        guard !parameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    /// 시퀀스 처음부터 끝까지 덮는 바탕 영상 트랙. 층으로 그리지 않으므로 화면에는 보이지 않는다.
    private static func addBlankBase(to composition: AVMutableComposition, duration: CMTime) async {
        do {
            let source = AVURLAsset(url: try await BlankVideo.url())
            guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first,
                  let base = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return }
            try base.insertTimeRange(CMTimeRange(start: .zero, duration: BlankVideo.duration), of: sourceVideo, at: .zero)
            base.scaleTimeRange(CMTimeRange(start: .zero, duration: BlankVideo.duration), toDuration: duration)
        } catch {
            Logger.playback.error("바탕 영상을 만들지 못함: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 방향 정보를 반영해 바로 선 이미지로 불러온다. 읽지 못하면 `nil`.
    private static func loadImage(at url: URL) -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumImagePixelSize,
              ] as CFDictionary)
        else {
            Logger.playback.error("합성에서 이미지를 읽지 못함: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return CIImage(cgImage: image)
    }
}
