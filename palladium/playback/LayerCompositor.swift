import AVFoundation
import CoreImage

/// 한 구간에 그릴 층 하나. 합성기는 아래 층부터 위 층 순서로 겹쳐 그린다.
nonisolated struct CompositionLayer {
    enum Content {
        /// 합성의 영상 트랙에서 그 시각의 프레임을 가져온다. 원본 크기와 회전 정보로 화면에 맞춘다.
        case video(trackID: CMPersistentTrackID, naturalSize: CGSize, preferredTransform: CGAffineTransform)
        /// 이미지(정지 화면).
        case image(CIImage)
    }

    let content: Content
    let transform: ClipTransform
}

/// 시퀀스 구간 하나와 그 구간에 그릴 층들. 빈 구간은 층이 없어 검은 화면이다.
final nonisolated class LayerInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [CompositionLayer]

    init(timeRange: CMTimeRange, layers: [CompositionLayer]) {
        self.timeRange = timeRange
        self.layers = layers
        let trackIDs = layers.compactMap { layer -> CMPersistentTrackID? in
            if case let .video(trackID, _, _) = layer.content {
                return trackID
            }
            return nil
        }
        requiredSourceTrackIDs = trackIDs.isEmpty ? nil : trackIDs.map { NSNumber(value: $0) }
    }
}

/// 여러 영상 트랙과 이미지를 클립마다의 위치·크기·불투명도로 겹쳐 그린다(Core Image). 미리보기와 내보내기가 같은 합성기를 쓴다.
final nonisolated class LayerCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    private let context = CIContext()

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? LayerInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "palladium.LayerCompositor", code: 1))
            return
        }
        let renderSize = request.renderContext.size
        let canvas = CGRect(origin: .zero, size: renderSize)
        var image = CIImage(color: .black).cropped(to: canvas)
        for layer in instruction.layers {
            guard let layerImage = Self.image(for: layer, request: request, renderSize: renderSize) else { continue }
            image = layerImage.composited(over: image)
        }
        context.render(image.cropped(to: canvas), to: output)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Layers

    /// 층을 화면 좌표(Core Image는 왼쪽 아래 원점)에 놓은 이미지. 프레임을 얻지 못하면 `nil`.
    private static func image(for layer: CompositionLayer, request: AVAsynchronousVideoCompositionRequest, renderSize: CGSize) -> CIImage? {
        let placed: CIImage
        switch layer.content {
        case let .video(trackID, naturalSize, preferredTransform):
            guard let buffer = request.sourceFrame(byTrackID: trackID) else { return nil }
            let transform = videoTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                clipTransform: layer.transform,
                renderSize: renderSize
            )
            placed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        case let .image(source):
            placed = source.transformed(by: imageTransform(imageSize: source.extent.size, clipTransform: layer.transform, renderSize: renderSize))
        }
        return applyingOpacity(layer.transform.opacity, to: placed)
    }

    /// 영상 프레임(회전 전 원본)을 화면 위 클립 사각형으로 옮기는 Core Image 좌표 변환.
    /// AVFoundation의 회전 정보와 클립 사각형은 왼쪽 위 원점이라, 원본과 화면의 세로축을 뒤집어 맞춘다.
    static func videoTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        clipTransform: ClipTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard displayed.width > 0, displayed.height > 0 else { return .identity }
        let frame = clipTransform.frame(contentSize: displayed.size, in: renderSize)
        let topLeft = preferredTransform
            .concatenating(CGAffineTransform(translationX: -displayed.minX, y: -displayed.minY))
            .concatenating(CGAffineTransform(scaleX: frame.width / displayed.width, y: frame.height / displayed.height))
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: naturalSize.height)
        let flipRender = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
        return flipSource.concatenating(topLeft).concatenating(flipRender)
    }

    /// 이미지를 화면 위 클립 사각형으로 옮기는 Core Image 좌표 변환(이미지는 이미 바로 선 방향이다).
    static func imageTransform(imageSize: CGSize, clipTransform: ClipTransform, renderSize: CGSize) -> CGAffineTransform {
        guard imageSize.width > 0, imageSize.height > 0 else { return .identity }
        let frame = clipTransform.frame(contentSize: imageSize, in: renderSize)
        return CGAffineTransform(scaleX: frame.width / imageSize.width, y: frame.height / imageSize.height)
            .concatenating(CGAffineTransform(translationX: frame.minX, y: renderSize.height - frame.maxY))
    }

    private static func applyingOpacity(_ opacity: Double, to image: CIImage) -> CIImage {
        guard opacity < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }
}
