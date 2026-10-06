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
    /// 원본 영상의 프레임레이트를 따른 프레임 간격(영상이 없으면 30fps).
    var frameDuration = OutputFrameRate.defaultDuration
}

/// 시퀀스의 모든 영상 트랙(아래 트랙이 먼저, 위 트랙이 그 위에)과 이미지 클립을 클립마다의 위치·크기·불투명도로 겹쳐 그리고(#5 2단계, #9),
/// 영상 클립의 소리와 오디오 트랙을 함께 넣는다. 자막은 맨 위에 그린다(#4). 그리기는 `LayerCompositor`가 한다.
nonisolated enum SequenceComposer {
    /// 화면비 프리셋의 기본 짧은 변(픽셀). 미리보기는 이 크기로 그리고, 자막 글자 크기의 기준이다.
    static let renderShortSide = 1080.0
    /// 이미지 층을 불러올 때의 최대 긴 변(픽셀). 화면보다 크게 불러 와도 보이는 차이가 없어 메모리를 아낀다.
    static let maximumImagePixelSize = 2160

    // MARK: - Queries

    /// 화면비 프리셋과 짧은 변으로 정한 출력 크기. 인코더가 받도록 가로·세로를 짝수로 맞춘다.
    static func renderSize(for preset: AspectRatioPreset, shortSide: Double = renderShortSide) -> CGSize {
        let width = Double(preset.widthRatio)
        let height = Double(preset.heightRatio)
        let scale = shortSide / min(width, height)
        let even = { (value: Double) in (value / 2).rounded() * 2 }
        return CGSize(width: even(width * scale), height: even(height * scale))
    }

    /// 해상도 설정에 따른 짧은 변. 원본을 따르면 시퀀스에 쓰인 가장 큰 영상의 짧은 변(최대 4K)이고, 영상이 없으면 1080이다.
    static func shortSide(for resolution: ExportResolution, sourceShortSides: [Double]) -> Double {
        if let fixed = resolution.fixedShortSide {
            return fixed
        }
        guard let largest = sourceShortSides.max() else { return renderShortSide }
        return min(largest, ExportResolution.maximumShortSide)
    }

    // MARK: - Composition

    /// 클립이 하나도 없으면 `nil`. 원본을 읽지 못한 클립은 건너뛰고(그 자리는 비어 있음) 나머지로 합성한다.
    /// 프레임레이트는 원본 영상 중 가장 높은 값을 따른다. `resolution`의 기본(1080p)은 미리보기용이고, 내보내기는 고른 값을 넘긴다.
    static func makeComposition(
        sequence: EditSequence,
        assets: [MediaAsset],
        aspectRatio: AspectRatioPreset,
        resolution: ExportResolution = .hd1080,
        resolveURL: (MediaAsset) -> URL
    ) async -> SequenceComposition? {
        guard sequence.duration > .zero else { return nil }
        let composition = AVMutableComposition()
        // 층으로 그릴 클립: (타임라인 구간, 층, 쌓는 순서 — 클수록 위).
        var placedLayers: [(range: CMTimeRange, layer: CompositionLayer, order: Int)] = []
        var images: [MediaAsset.ID: CIImage] = [:]
        // 합성 오디오 트랙마다의 음량 변화(클립 음량·크로스페이드).
        var ramps: [VolumeRamp] = []
        // 출력 프레임레이트·해상도를 정할 원본 영상 정보.
        var sourceFrameTimings: [SourceFrameTiming] = []
        var sourceShortSides: [Double] = []

        for (trackIndex, track) in sequence.tracks.enumerated() where track.kind == .video {
            // 트랙 배열은 화면 위쪽부터라, 앞에 있을수록 위에 그린다.
            let order = sequence.tracks.count - trackIndex
            // 전환·크로스페이드가 있으면 앞뒤 클립이 컷 지점에서 겹치므로 합성 트랙 두 줄(A/B)을 번갈아 쓴다.
            let videoRolls = Rolls(composition: composition, mediaType: .video)
            let soundRolls = Rolls(composition: composition, mediaType: .audio)
            for clip in track.clips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                guard let asset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                let edges = TransitionEdges(track: track, clip: clip)
                let videoTrack = videoRolls.track(switching: edges.transition != nil)
                let soundTrack = soundRolls.track(switching: edges.crossfadeIn != nil)
                let layerRange = edges.videoRange(of: clip)
                let fade = edges.transition.map { CompositionLayer.Fade(range: edges.transitionRange(of: clip), kind: $0.kind) }
                if asset.kind == .image {
                    if images[asset.id] == nil {
                        images[asset.id] = loadImage(at: resolveURL(asset))
                    }
                    if let image = images[asset.id] {
                        placedLayers.append((layerRange, CompositionLayer(content: .image(image), transform: clip.transform, fade: fade, colorAdjustment: clip.colorAdjustment), order))
                    }
                    continue
                }
                // 원본 에셋을 변수로 붙잡아 둬야 한다. 임시로 만든 에셋이 사라지면 그 트랙을 합성에 넣지 못한다.
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceVideo = try await source.loadTracks(withMediaType: .video).first, let videoTrack {
                        try await insert(clip, of: sourceVideo, into: videoTrack, lead: edges.videoLead, tail: edges.videoTail, freezesMissingFrames: true)
                        let (naturalSize, preferredTransform, frameRate, minFrameDuration) = try await sourceVideo.load(
                            .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration
                        )
                        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).size
                        sourceShortSides.append(min(abs(displayed.width), abs(displayed.height)))
                        sourceFrameTimings.append(SourceFrameTiming(nominalFrameRate: frameRate, minFrameDuration: minFrameDuration))
                        let content = CompositionLayer.Content.video(trackID: videoTrack.trackID, naturalSize: naturalSize, preferredTransform: preferredTransform)
                        placedLayers.append((layerRange, CompositionLayer(content: content, transform: clip.transform, fade: fade, colorAdjustment: clip.colorAdjustment), order))
                    }
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let soundTrack {
                        try await insert(clip, of: sourceAudio, into: soundTrack, lead: edges.audioLead, tail: edges.audioTail, freezesMissingFrames: false)
                        ramps += edges.volumeRamps(of: clip, trackID: soundTrack.trackID, volume: Float(sequence.effectiveVolume(of: clip.id)))
                    }
                } catch {
                    Logger.playback.error("합성에서 클립을 건너뜀: \(asset.name, privacy: .public), \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // 오디오 트랙: 트랙마다 합성 오디오 트랙 두 줄(크로스페이드용).
        for track in sequence.tracks where track.kind == .audio {
            let audioRolls = Rolls(composition: composition, mediaType: .audio)
            for clip in track.clips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                guard let asset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                let edges = TransitionEdges(track: track, clip: clip)
                let audioTrack = audioRolls.track(switching: edges.crossfadeIn != nil)
                let source = AVURLAsset(url: resolveURL(asset))
                do {
                    if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first, let audioTrack {
                        try await insert(clip, of: sourceAudio, into: audioTrack, lead: edges.audioLead, tail: edges.audioTail, freezesMissingFrames: false)
                        ramps += edges.volumeRamps(of: clip, trackID: audioTrack.trackID, volume: Float(sequence.effectiveVolume(of: clip.id)))
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
        let audioMix = makeAudioMix(composition: composition, ramps: ramps)
        let frameDuration = OutputFrameRate.frameDuration(forSources: sourceFrameTimings)
        guard !placedLayers.isEmpty else {
            return SequenceComposition(asset: composition, videoComposition: nil, audioMix: audioMix, duration: duration, frameDuration: frameDuration)
        }
        let size = renderSize(for: aspectRatio, shortSide: shortSide(for: resolution, sourceShortSides: sourceShortSides))
        return SequenceComposition(
            asset: composition,
            videoComposition: makeVideoComposition(
                layers: placedLayers, masks: sequence.masks, duration: duration, renderSize: size, frameDuration: frameDuration
            ),
            audioMix: audioMix,
            duration: duration,
            frameDuration: frameDuration
        )
    }

    /// 클립 경계마다 구간을 나누고, 구간마다 그 시각에 걸친 층을 아래부터 쌓는다. 처음부터 끝까지 빈틈없이 덮는다.
    private static func makeVideoComposition(
        layers: [(range: CMTimeRange, layer: CompositionLayer, order: Int)],
        masks: [Mask],
        duration: CMTime,
        renderSize: CGSize,
        frameDuration: CMTime
    ) -> AVVideoComposition {
        let boundaries = Set([CMTime.zero, duration] + layers.flatMap { [$0.range.start, $0.range.end] } + masks.flatMap { [$0.range.start, $0.range.end] })
            .filter { $0 >= .zero && $0 <= duration }
            .sorted()
        let instructions = zip(boundaries, boundaries.dropFirst()).compactMap { start, end -> LayerInstruction? in
            guard start < end else { return nil }
            let active = layers
                .filter { $0.range.start <= start && start < $0.range.end }
                // 같은 트랙에서는 나중에 시작한 클립(전환으로 나타나는 클립)을 위에 그린다.
                .sorted { ($0.order, $0.range.start.seconds) < ($1.order, $1.range.start.seconds) }
                .map(\.layer)
            let activeMasks = masks.filter { $0.range.start <= start && start < $0.range.end }
            return LayerInstruction(timeRange: CMTimeRange(start: start, end: end), layers: active, masks: activeMasks)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = LayerCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions
        return videoComposition
    }

    /// 합성 오디오 트랙마다 클립 음량과 크로스페이드를 음량 변화로 둔다.
    private static func makeAudioMix(composition: AVComposition, ramps: [VolumeRamp]) -> AVAudioMix? {
        let parameters = composition.tracks(withMediaType: .audio).map { track in
            let trackParameters = AVMutableAudioMixInputParameters(track: track)
            for ramp in ramps.filter({ $0.trackID == track.trackID }).sorted(by: { $0.range.start < $1.range.start }) {
                trackParameters.setVolumeRamp(fromStartVolume: ramp.from, toEndVolume: ramp.to, timeRange: ramp.range)
            }
            return trackParameters
        }
        guard !parameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    /// 클립을 합성 트랙에 넣는다. 전환으로 컷 앞(`lead`)·뒤(`tail`)까지 더 보여야 하면 원본의 앞뒤 여분을 쓰고,
    /// 여분이 모자라면 영상은 첫·끝 프레임을 멈춰 채우고 소리는 비워 둔다.
    private static func insert(
        _ clip: Clip,
        of source: AVAssetTrack,
        into track: AVMutableCompositionTrack,
        lead: CMTime,
        tail: CMTime,
        freezesMissingFrames: Bool
    ) async throws {
        let sourceEnd = try await source.load(.timeRange).end
        // 속도를 바꾼 클립은 원본 여분을 쓰지 않고 멈춘 프레임(소리는 무음)으로 채운다.
        let usesHandles = clip.speed == 1
        let handleBefore = usesHandles ? CMTimeMinimum(lead, clip.sourceRange.start) : .zero
        let handleAfter = usesHandles ? CMTimeMinimum(tail, CMTimeMaximum(sourceEnd - clip.sourceRange.end, .zero)) : .zero
        let sourceRange = CMTimeRange(start: clip.sourceRange.start - handleBefore, end: clip.sourceRange.end + handleAfter)
        let missingBefore = lead - handleBefore
        let missingAfter = tail - handleAfter
        // 멈춰 쓸 프레임 하나의 길이는 원본의 프레임 간격이다.
        let sourceFrame = try await source.load(.minFrameDuration)
        let frameDuration = sourceFrame.isNumeric && sourceFrame > .zero ? sourceFrame : OutputFrameRate.defaultDuration

        if freezesMissingFrames, missingBefore > .zero {
            let frame = CMTimeRange(start: sourceRange.start, duration: frameDuration)
            try track.insertTimeRange(frame, of: source, at: clip.timelineStart - lead)
            track.scaleTimeRange(CMTimeRange(start: clip.timelineStart - lead, duration: frameDuration), toDuration: missingBefore)
        }
        try track.insertTimeRange(sourceRange, of: source, at: clip.timelineStart - handleBefore)
        if clip.speed != 1 {
            track.scaleTimeRange(CMTimeRange(start: clip.timelineStart, duration: clip.sourceRange.duration), toDuration: clip.timelineDuration)
        }
        if freezesMissingFrames, missingAfter > .zero {
            let frameStart = clip.timelineRange.end + handleAfter
            try track.insertTimeRange(CMTimeRange(start: sourceRange.end - frameDuration, duration: frameDuration), of: source, at: frameStart)
            track.scaleTimeRange(CMTimeRange(start: frameStart, duration: frameDuration), toDuration: missingAfter)
        }
    }

    /// 시퀀스 처음부터 끝까지 덮는 바탕 영상 트랙. 층으로 그리지 않으므로 화면에는 보이지 않는다.
    private static func addBlankBase(to composition: AVMutableComposition, duration: CMTime) async {
        do {
            let source = try AVURLAsset(url: await BlankVideo.url())
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

/// 합성 오디오 트랙 하나의 한 구간 음량 변화.
nonisolated struct VolumeRamp {
    let trackID: CMPersistentTrackID
    let range: CMTimeRange
    let from: Float
    let to: Float
}

/// 트랙 하나에 쓰는 합성 트랙 두 줄. 전환으로 앞 클립과 겹치는 클립만 다른 줄로 바꿔 넣는다.
private final nonisolated class Rolls {
    private let tracks: [AVMutableCompositionTrack?]
    private var index = 0

    init(composition: AVMutableComposition, mediaType: AVMediaType) {
        tracks = [
            composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid),
            composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid),
        ]
    }

    func track(switching: Bool) -> AVMutableCompositionTrack? {
        if switching {
            index = 1 - index
        }
        return tracks[index]
    }
}

/// 클립 앞뒤의 전환·크로스페이드. 컷 지점을 가운데 두고 앞뒤로 절반씩 걸친다(#8).
private nonisolated struct TransitionEdges {
    let transition: ClipTransition?
    let crossfadeIn: CMTime?
    let crossfadeOut: CMTime?
    let transitionOut: ClipTransition?

    init(track: Track, clip: Clip) {
        transition = track.effectiveTransition(into: clip)
        crossfadeIn = track.effectiveAudioCrossfade(into: clip)
        let next = track.clips.first { $0.timelineStart == clip.timelineRange.end && $0.id != clip.id }
        transitionOut = next.flatMap { track.effectiveTransition(into: $0) }
        crossfadeOut = next.flatMap { track.effectiveAudioCrossfade(into: $0) }
    }

    var videoLead: CMTime {
        half(transition?.duration)
    }

    var videoTail: CMTime {
        half(transitionOut?.duration)
    }

    var audioLead: CMTime {
        half(crossfadeIn)
    }

    var audioTail: CMTime {
        half(crossfadeOut)
    }

    /// 전환으로 컷 앞뒤까지 늘어난, 화면에 그릴 구간.
    func videoRange(of clip: Clip) -> CMTimeRange {
        CMTimeRange(start: clip.timelineStart - videoLead, end: clip.timelineRange.end + videoTail)
    }

    /// 이 클립이 나타나는 전환 구간.
    func transitionRange(of clip: Clip) -> CMTimeRange {
        CMTimeRange(start: clip.timelineStart - videoLead, end: clip.timelineStart + videoLead)
    }

    /// 크로스페이드 구간에서는 0과 클립 음량 사이를 오가고, 나머지는 클립 음량 그대로다.
    func volumeRamps(of clip: Clip, trackID: CMPersistentTrackID, volume: Float) -> [VolumeRamp] {
        let start = clip.timelineStart
        let end = clip.timelineRange.end
        var ramps: [VolumeRamp] = []
        if audioLead > .zero {
            ramps.append(VolumeRamp(trackID: trackID, range: CMTimeRange(start: start - audioLead, end: start + audioLead), from: 0, to: volume))
        }
        let steadyRange = CMTimeRange(start: start + audioLead, end: end - audioTail)
        if steadyRange.duration > .zero {
            ramps.append(VolumeRamp(trackID: trackID, range: steadyRange, from: volume, to: volume))
        }
        if audioTail > .zero {
            ramps.append(VolumeRamp(trackID: trackID, range: CMTimeRange(start: end - audioTail, end: end + audioTail), from: volume, to: 0))
        }
        return ramps
    }

    private func half(_ duration: CMTime?) -> CMTime {
        guard let duration else { return .zero }
        return CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
    }
}
