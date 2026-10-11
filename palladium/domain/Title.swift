import CoreGraphics
import CoreMedia
import Foundation

/// 타이틀(#76): 영상 트랙에 클립으로 놓고 화면 아무 곳에 꾸며 얹는 글자. 자막과 달리 트랙의 클립이라 위치·크기·회전·불투명도(트랜스폼)와
/// 키프레임(#67, 페이드 인·아웃)을 그대로 쓴다. 크기는 화면 짧은 변 1080 기준 포인트다.
nonisolated struct TitleText {
    var text = "제목"
    /// 글꼴 PostScript 이름. 이 Mac에 없으면 기본 글꼴로 그린다.
    var fontName = SubtitleStyle.defaultFontName
    var fontSize = 120.0
    var textColor = SubtitleRGB.white
    /// 외곽선 굵기(포인트). 0이면 없다.
    var outlineWidth = 0.0
    var outlineColor = SubtitleRGB.black
    var hasShadow = true
    var backgroundColor = SubtitleRGB.black
    /// 배경 상자 불투명도(0~1). 0이면 배경이 없다.
    var backgroundOpacity = 0.0

    static let fontSizeRange = 24.0 ... 400.0
    static let outlineWidthRange = 0.0 ... 20.0
    /// 새 타이틀의 길이.
    static let defaultDuration = CMTime(value: 5, timescale: 1)
}

nonisolated extension TitleText: Equatable {}

// MARK: - Commands

nonisolated extension TitleText {
    /// 범위를 벗어난 값은 가장 가까운 값으로 맞춘다. 글자가 비면 "제목"으로 둔다(보이지 않는 클립이 되지 않게).
    mutating func clamp() {
        fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        outlineWidth = min(max(outlineWidth, Self.outlineWidthRange.lowerBound), Self.outlineWidthRange.upperBound)
        backgroundOpacity = min(max(backgroundOpacity, 0), 1)
        textColor = textColor.clamped
        outlineColor = outlineColor.clamped
        backgroundColor = backgroundColor.clamped
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "제목"
        }
        if fontName.isEmpty {
            fontName = SubtitleStyle.defaultFontName
        }
    }
}

// MARK: - Clip

nonisolated extension Clip {
    /// 타이틀 클립이 가리키는 원본 ID. 타이틀은 원본 파일이 없어 프로젝트 원본 목록에 없는 고정 ID를 쓴다.
    static let titleAssetID = UUID(uuidString: "7171E000-0000-4000-8000-000000000076")!

    /// 타이틀 클립인지.
    var isTitle: Bool {
        title != nil
    }

    /// `time`에 놓는 기본 길이(5초)의 새 타이틀 클립.
    static func makeTitle(_ title: TitleText = TitleText(), at time: CMTime) -> Clip? {
        var clip = Clip(assetID: titleAssetID, sourceRange: CMTimeRange(start: .zero, duration: TitleText.defaultDuration), timelineStart: CMTimeMaximum(time, .zero))
        clip?.title = title
        return clip
    }

    /// 페이드 인·아웃(#76): 불투명도 키프레임을 처음 0 → `duration` 뒤 지금 불투명도 → 끝 `duration` 전 지금 불투명도 → 끝 0으로 둔다.
    /// 길이는 클립 길이의 4분의 1을 넘지 않는다. 트랜스폼 키프레임이 이미 있으면 바꾸지 않는다(손으로 만든 움직임을 덮지 않게).
    mutating func addFade(duration: CMTime) {
        guard animation.transform.isEmpty else { return }
        let fade = CMTimeMinimum(duration, CMTimeMultiplyByRatio(timelineDuration, multiplier: 1, divisor: 4))
        guard fade > .zero else { return }
        var hidden = transform
        hidden.opacity = 0
        let start = timelineStart
        let end = timelineRange.end
        for (time, value) in [(start, hidden), (start + fade, transform), (end - fade, transform), (end, hidden)] {
            animation.transform.setKeyframe(value, at: sourceTime(atTimeline: time))
        }
    }
}

// MARK: - ClipTransform

nonisolated extension ClipTransform {
    /// 원래 크기(`naturalSize`, 화면 픽셀)를 그대로 배율만큼 키워 가운데 위치에 놓은 사각형(왼쪽 위 원점). 타이틀처럼 화면에 맞춰 늘리지 않는 내용에 쓴다.
    func frame(naturalSize: CGSize, in renderSize: CGSize) -> CGRect {
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        return CGRect(x: centerX * renderSize.width - size.width / 2, y: centerY * renderSize.height - size.height / 2, width: size.width, height: size.height)
    }
}
