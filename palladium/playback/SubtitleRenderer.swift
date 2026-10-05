import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// 자막 하나를 결과물 화면 위의 글자 이미지로 그린다(#4). 미리보기와 내보내기가 같은 합성기에서 쓴다.
nonisolated enum SubtitleRenderer {
    /// 한 줄 너비의 최대치(화면 너비 대비).
    static let maximumWidthRatio = 0.9
    /// 위·아래 자막과 화면 가장자리 사이 여백(화면 높이 대비).
    static let edgeMarginRatio = 0.06
    static let fontName = "AppleSDGothicNeo-Bold" as CFString

    /// Core Image 좌표(왼쪽 아래 원점)에 놓인 자막 이미지. 글자가 비어 있으면 `nil`.
    static func image(for subtitle: Subtitle, renderSize: CGSize) -> CIImage? {
        let text = subtitle.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }
        let scale = min(renderSize.width, renderSize.height) / SequenceComposer.renderShortSide
        let fontSize = subtitle.style.fontSize * scale
        let padding = (fontSize * 0.3).rounded()

        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor(subtitle.style.color),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let maximumWidth = renderSize.width * maximumWidthRatio - padding * 2
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maximumWidth, height: .greatestFiniteMagnitude), nil
        )
        let textSize = CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
        let boxSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        guard let context = CGContext(
            data: nil, width: Int(boxSize.width), height: Int(boxSize.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        if subtitle.style.hasBackground {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: boxSize), cornerWidth: padding, cornerHeight: padding, transform: nil))
            context.fillPath()
        }
        let textRect = CGRect(origin: CGPoint(x: padding, y: padding), size: textSize)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let cgImage = context.makeImage() else { return nil }

        let x = ((renderSize.width - boxSize.width) / 2).rounded()
        let margin = (renderSize.height * edgeMarginRatio).rounded()
        let y = switch subtitle.style.position {
        case .bottom: margin
        case .middle: ((renderSize.height - boxSize.height) / 2).rounded()
        case .top: renderSize.height - margin - boxSize.height
        }
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func textColor(_ color: SubtitleColor) -> CGColor {
        switch color {
        case .white: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .yellow: CGColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        }
    }
}
