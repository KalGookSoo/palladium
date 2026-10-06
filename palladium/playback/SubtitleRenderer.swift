import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// 자막 하나를 결과물 화면 위의 글자 이미지로 그린다(#4). 미리보기와 내보내기가 같은 합성기에서 쓴다.
/// 위치·글꼴·글자색·배경색·불투명도는 `SubtitleStyle`을 따른다(#82).
nonisolated enum SubtitleRenderer {
    /// 한 줄 너비의 최대치(화면 너비 대비).
    static let maximumWidthRatio = 0.9

    /// Core Image 좌표(왼쪽 아래 원점)에 놓인 자막 이미지. 글자가 비어 있으면 `nil`.
    static func image(for subtitle: Subtitle, renderSize: CGSize) -> CIImage? {
        guard let layout = layout(for: subtitle, renderSize: renderSize) else { return nil }
        guard let context = CGContext(
            data: nil, width: Int(layout.frame.width), height: Int(layout.frame.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let style = subtitle.style
        if style.backgroundOpacity > 0 {
            context.setFillColor(cgColor(style.backgroundColor, alpha: style.backgroundOpacity))
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: layout.frame.size), cornerWidth: layout.padding, cornerHeight: layout.padding, transform: nil))
            context.fillPath()
        }
        let textRect = CGRect(origin: CGPoint(x: layout.padding, y: layout.padding), size: layout.textSize)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let cgImage = context.makeImage() else { return nil }
        // 왼쪽 위 원점 좌표를 Core Image 좌표로 바꾼다.
        let y = renderSize.height - layout.frame.maxY
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: layout.frame.minX, y: y))
    }

    /// 화면(왼쪽 위 원점)에 그려지는 자막 상자. 미리보기 손잡이와 방향키 이동이 실제로 보이는 자리에서 시작하는 데 쓴다.
    static func frame(for subtitle: Subtitle, renderSize: CGSize) -> CGRect? {
        layout(for: subtitle, renderSize: renderSize)?.frame
    }

    /// 이 Mac에 그 글꼴이 있는지. 없으면 기본 글꼴로 그린다.
    static func isFontAvailable(_ fontName: String) -> Bool {
        let font = CTFontCreateWithName(fontName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == fontName
    }

    // MARK: - Layout

    private struct Layout {
        let framesetter: CTFramesetter
        let textSize: CGSize
        let padding: Double
        let frame: CGRect
    }

    private static func layout(for subtitle: Subtitle, renderSize: CGSize) -> Layout? {
        let text = subtitle.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }
        let style = subtitle.style
        let scale = min(renderSize.width, renderSize.height) / SequenceComposer.renderShortSide
        let fontSize = style.fontSize * scale
        let padding = (fontSize * 0.3).rounded()

        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let fontName = isFontAvailable(style.fontName) ? style.fontName : SubtitleStyle.defaultFontName
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(style.textColor, alpha: style.textOpacity),
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
        let origin = style.boxOrigin(boxSize: boxSize, renderSize: renderSize)
        return Layout(framesetter: framesetter, textSize: textSize, padding: padding, frame: CGRect(origin: origin, size: boxSize))
    }

    private static func cgColor(_ color: SubtitleRGB, alpha: Double) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }
}
