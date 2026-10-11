import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// 타이틀(#76) 글자를 그린 이미지. 글자를 감싸는 상자 크기(화면 픽셀)로 그리고, 화면 위 자리·크기·각도는 클립 트랜스폼이 정한다.
/// 미리보기와 내보내기가 같은 합성기에서 쓴다. 여러 줄은 가운데 맞춤이고, 외곽선·그림자·배경 상자를 그릴 수 있다.
nonisolated enum TitleRenderer {
    /// 글자 상자의 최대 폭(화면 너비 대비). 넘으면 줄을 바꾼다.
    static let maximumWidthRatio = 0.9

    /// 타이틀 상자의 원래 크기(화면 픽셀, 트랜스폼 배율 1일 때). 미리보기 손잡이가 테두리를 그리는 데 쓴다.
    static func naturalSize(of title: TitleText, renderSize: CGSize) -> CGSize {
        layout(for: title, renderSize: renderSize)?.boxSize ?? .zero
    }

    /// 상자 크기의 이미지(왼쪽 아래 원점, 0,0에서 시작). 그리지 못하면 `nil`.
    static func image(for title: TitleText, renderSize: CGSize) -> CIImage? {
        guard let layout = layout(for: title, renderSize: renderSize),
              let context = CGContext(
                  data: nil, width: Int(layout.boxSize.width), height: Int(layout.boxSize.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        if title.backgroundOpacity > 0 {
            context.setFillColor(cgColor(title.backgroundColor, alpha: title.backgroundOpacity))
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: layout.boxSize), cornerWidth: layout.padding, cornerHeight: layout.padding, transform: nil))
            context.fillPath()
        }
        if title.hasShadow {
            context.setShadow(offset: CGSize(width: layout.fontSize * 0.04, height: -layout.fontSize * 0.04), blur: layout.fontSize * 0.08, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        }
        let textRect = CGRect(origin: CGPoint(x: layout.padding, y: layout.padding), size: layout.textSize)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Layout

    private struct Layout {
        let framesetter: CTFramesetter
        let textSize: CGSize
        let padding: Double
        let fontSize: Double

        var boxSize: CGSize {
            CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        }
    }

    private static func layout(for title: TitleText, renderSize: CGSize) -> Layout? {
        let text = title.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }
        let scale = min(renderSize.width, renderSize.height) / SequenceComposer.renderShortSide
        let fontSize = title.fontSize * scale
        let outline = title.outlineWidth * scale
        // 외곽선·그림자가 상자 밖으로 잘리지 않게 여백을 둔다.
        let padding = (fontSize * 0.25 + outline).rounded()

        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let fontName = SubtitleRenderer.isFontAvailable(title.fontName) ? title.fontName : SubtitleStyle.defaultFontName
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(title.textColor, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ]
        if outline > 0 {
            // 음수 굵기는 글자를 채우고 외곽선을 함께 그린다(글꼴 크기 대비 %).
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -outline / fontSize * 100
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = cgColor(title.outlineColor, alpha: 1)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: renderSize.width * maximumWidthRatio - padding * 2, height: .greatestFiniteMagnitude), nil
        )
        return Layout(framesetter: framesetter, textSize: CGSize(width: ceil(fitted.width), height: ceil(fitted.height)), padding: padding, fontSize: fontSize)
    }

    private static func cgColor(_ color: SubtitleRGB, alpha: Double) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }
}
