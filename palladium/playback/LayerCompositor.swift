import AVFoundation
import CoreImage

/// 한 구간에 그릴 층 하나. 합성기는 아래 층부터 위 층 순서로 겹쳐 그린다.
nonisolated struct CompositionLayer {
    enum Content {
        /// 합성의 영상 트랙에서 그 시각의 프레임을 가져온다. 원본 크기와 회전 정보로 화면에 맞춘다.
        case video(trackID: CMPersistentTrackID, naturalSize: CGSize, preferredTransform: CGAffineTransform)
        /// 이미지(정지 화면).
        case image(CIImage)
        /// 자막(#4). 위치는 자막 스타일이 정하고 `transform`은 쓰지 않는다.
        case subtitle(Subtitle)
    }

    /// 앞 클립 위로 나타나는 전환(#8). 구간 동안 0에서 1로 나아간다.
    struct Fade {
        let range: CMTimeRange
        let kind: TransitionKind
    }

    let content: Content
    let transform: ClipTransform
    var fade: Fade?
    /// 밝기·대비·채도(#61). 화면에 놓기 전 원본 이미지에 적용한다.
    var colorAdjustment = ColorAdjustment()
    /// 잘라낼 화면(#85). 영상 층에만 쓴다. 위치·크기(`transform`)는 잘린 화면을 기준으로 한다.
    var crop = ClipCrop()
}

/// 시퀀스 구간 하나와 그 구간에 그릴 층들. 빈 구간은 층이 없어 검은 화면이다.
final nonisolated class LayerInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [CompositionLayer]
    /// 이 구간에 걸친 마스크(#59). 자막 아래, 영상·이미지 층 위에 적용한다.
    let masks: [Mask]

    init(timeRange: CMTimeRange, layers: [CompositionLayer], masks: [Mask] = []) {
        self.timeRange = timeRange
        self.layers = layers
        self.masks = masks
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
    /// 그려 둔 자막 이미지. 같은 자막이 여러 프레임에 이어 나오므로 다시 그리지 않는다.
    private let subtitleCache = NSCache<NSString, CIImage>()

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
        var masksApplied = instruction.masks.isEmpty
        for layer in instruction.layers {
            // 자막은 가리지 않도록, 자막 층을 그리기 직전에 마스크를 적용한다.
            if !masksApplied, case .subtitle = layer.content {
                image = Self.applying(instruction.masks, to: image, renderSize: renderSize)
                masksApplied = true
            }
            guard var layerImage = placedImage(for: layer, request: request, renderSize: renderSize) else { continue }
            if let fade = layer.fade {
                layerImage = Self.applying(fade, at: request.compositionTime, to: layerImage, renderSize: renderSize)
            }
            image = layerImage.composited(over: image)
        }
        if !masksApplied {
            image = Self.applying(instruction.masks, to: image, renderSize: renderSize)
        }
        context.render(image.cropped(to: canvas), to: output)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Layers

    /// 층을 화면 좌표(Core Image는 왼쪽 아래 원점)에 놓은 이미지. 프레임을 얻지 못하면 `nil`.
    private func placedImage(for layer: CompositionLayer, request: AVAsynchronousVideoCompositionRequest, renderSize: CGSize) -> CIImage? {
        let placed: CIImage
        switch layer.content {
        case let .video(trackID, naturalSize, preferredTransform):
            guard let buffer = request.sourceFrame(byTrackID: trackID) else { return nil }
            let transform = Self.videoTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                clipTransform: layer.transform,
                crop: layer.crop,
                renderSize: renderSize
            )
            placed = Self.cropping(Self.applying(layer.colorAdjustment, to: CIImage(cvPixelBuffer: buffer)).transformed(by: transform), by: layer.crop)
        case let .image(source):
            let adjusted = Self.applying(layer.colorAdjustment, to: source)
            placed = adjusted.transformed(by: Self.imageTransform(imageSize: source.extent.size, clipTransform: layer.transform, renderSize: renderSize))
        case let .subtitle(subtitle):
            return subtitleImage(subtitle, renderSize: renderSize)
        }
        return Self.applyingOpacity(layer.transform.opacity, to: placed)
    }

    private func subtitleImage(_ subtitle: Subtitle, renderSize: CGSize) -> CIImage? {
        let key = "\(subtitle.id)|\(subtitle.text)|\(subtitle.style)|\(renderSize)" as NSString
        if let cached = subtitleCache.object(forKey: key) {
            return cached
        }
        guard let image = SubtitleRenderer.image(for: subtitle, renderSize: renderSize) else { return nil }
        subtitleCache.setObject(image, forKey: key)
        return image
    }

    /// 영상 프레임(회전 전 원본)을 화면 위 클립 사각형으로 옮기는 Core Image 좌표 변환.
    /// AVFoundation의 회전 정보와 클립 사각형은 왼쪽 위 원점이라, 원본과 화면의 세로축을 뒤집어 맞춘다.
    /// 크롭(#85)이 있으면 잘린 화면이 클립 사각형에 오도록 원본 전체를 그만큼 크게·비켜 놓는다(바깥은 `cropping`이 잘라낸다).
    static func videoTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        clipTransform: ClipTransform,
        crop: ClipCrop = ClipCrop(),
        renderSize: CGSize
    ) -> CGAffineTransform {
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard displayed.width > 0, displayed.height > 0 else { return .identity }
        let frame = crop.fullFrame(forCroppedFrame: clipTransform.frame(contentSize: crop.croppedSize(of: displayed.size), in: renderSize))
        let topLeft = preferredTransform
            .concatenating(CGAffineTransform(translationX: -displayed.minX, y: -displayed.minY))
            .concatenating(CGAffineTransform(scaleX: frame.width / displayed.width, y: frame.height / displayed.height))
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: naturalSize.height)
        let flipRender = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
        return flipSource.concatenating(topLeft).concatenating(flipRender)
    }

    /// 화면에 놓은 원본 전체(`image.extent`)에서 잘린 화면 바깥을 잘라낸다(#85). Core Image는 왼쪽 아래 원점이라 아래 비율부터 잰다.
    /// 크롭이 없으면 그대로 둔다.
    private static func cropping(_ image: CIImage, by crop: ClipCrop) -> CIImage {
        guard !crop.isDefault else { return image }
        let full = image.extent
        let visible = crop.visibleRect
        return image.cropped(to: CGRect(
            x: full.minX + crop.left * full.width,
            y: full.minY + crop.bottom * full.height,
            width: visible.width * full.width,
            height: visible.height * full.height
        ))
    }

    /// 이미지를 화면 위 클립 사각형으로 옮기는 Core Image 좌표 변환(이미지는 이미 바로 선 방향이다).
    static func imageTransform(imageSize: CGSize, clipTransform: ClipTransform, renderSize: CGSize) -> CGAffineTransform {
        guard imageSize.width > 0, imageSize.height > 0 else { return .identity }
        let frame = clipTransform.frame(contentSize: imageSize, in: renderSize)
        return CGAffineTransform(scaleX: frame.width / imageSize.width, y: frame.height / imageSize.height)
            .concatenating(CGAffineTransform(translationX: frame.minX, y: renderSize.height - frame.maxY))
    }

    /// 마스크 영역만 흐리거나 모자이크한 화면. 마스크 사각형은 왼쪽 위 원점이라 Core Image 좌표로 뒤집는다.
    static func applying(_ masks: [Mask], to image: CIImage, renderSize: CGSize) -> CIImage {
        let canvas = CGRect(origin: .zero, size: renderSize)
        let shortSide = min(renderSize.width, renderSize.height)
        return masks.reduce(image) { current, mask in
            let topLeft = mask.area.rect(in: renderSize)
            let rect = CGRect(x: topLeft.minX, y: renderSize.height - topLeft.maxY, width: topLeft.width, height: topLeft.height)
            let filtered: CIImage = switch mask.effect {
            case .blur:
                current.clampedToExtent().applyingGaussianBlur(sigma: 4 + mask.strength * shortSide * 0.04).cropped(to: canvas)
            case .mosaic:
                current.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: 6 + mask.strength * shortSide * 0.06,
                    kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY),
                ]).cropped(to: canvas)
            }
            return filtered.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: current,
                kCIInputMaskImageKey: maskImage(shape: mask.shape, rect: rect, canvas: canvas),
            ]).cropped(to: canvas)
        }
    }

    /// 영역 안은 흰색, 밖은 검은색인 가림 판.
    private static func maskImage(shape: MaskShape, rect: CGRect, canvas: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: canvas)
        let white: CIImage
        switch shape {
        case .rectangle:
            white = CIImage(color: .white).cropped(to: rect)
        case .ellipse:
            // 반지름 1인 원을 그려 영역 크기의 타원으로 늘린다.
            let circle = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputRadius0": 0.97,
                "inputRadius1": 1.0,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
            ])?.outputImage?.cropped(to: CGRect(x: -1, y: -1, width: 2, height: 2)) ?? CIImage.empty()
            white = circle.transformed(by: CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2)
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        }
        return white.composited(over: black)
    }

    /// 전환 진행만큼 디졸브는 투명도를, 와이프는 왼쪽부터 보이는 폭을 정한다.
    static func applying(_ fade: CompositionLayer.Fade, at time: CMTime, to image: CIImage, renderSize: CGSize) -> CIImage {
        let elapsed = (time - fade.range.start).seconds / max(fade.range.duration.seconds, 0.001)
        let progress = min(max(elapsed, 0), 1)
        switch fade.kind {
        case .dissolve:
            return applyingOpacity(progress, to: image)
        case .wipe:
            return image.cropped(to: CGRect(x: 0, y: 0, width: renderSize.width * progress, height: renderSize.height))
        }
    }

    /// 화면에 놓기 전(바깥이 투명해지기 전) 원본 이미지에 색보정을 적용한다. 기본값이면 그대로 둔다.
    static func applying(_ adjustment: ColorAdjustment, to image: CIImage) -> CIImage {
        guard !adjustment.isDefault else { return image }
        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: adjustment.brightness,
            kCIInputContrastKey: adjustment.contrast,
            kCIInputSaturationKey: adjustment.saturation,
        ])
    }

    private static func applyingOpacity(_ opacity: Double, to image: CIImage) -> CIImage {
        guard opacity < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }
}
