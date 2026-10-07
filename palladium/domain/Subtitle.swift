import CoreGraphics
import CoreMedia
import Foundation

/// 결과물(시퀀스)의 시간에 붙는 자막 하나. 원본 클립과 상관없이 그 시각에 화면에 그린다(#4).
nonisolated struct Subtitle {
    let id: UUID
    var range: CMTimeRange
    var text: String
    var style = SubtitleStyle()

    /// 새 자막의 기본 길이.
    static let defaultDuration = CMTime(value: 3, timescale: 1)
    /// 시작·끝을 조정해도 남는 가장 짧은 길이.
    static let minimumDuration = CMTime(value: 1, timescale: 10)
}

/// 자막 모양. 크기는 화면 짧은 변 1080 기준 포인트다.
/// 위치는 화면 비율 좌표라 화면비를 바꿔도 같은 자리에 머문다(#82). 상자는 화면 가장자리 여백 안으로 맞춰 그린다.
nonisolated struct SubtitleStyle {
    var fontSize = 54.0
    /// 자막 상자 가운데의 가로·세로 위치(0~1, 왼쪽 위가 0). 기본은 화면 아래(여백에 붙음)다.
    var centerX = 0.5
    var centerY = 1.0
    /// 글꼴 PostScript 이름(글꼴 가족 + 굵기). 이 Mac에 없으면 기본 글꼴로 그린다.
    var fontName = Self.defaultFontName
    var textColor = SubtitleRGB.white
    /// 글자 불투명도(0~1).
    var textOpacity = 1.0
    var backgroundColor = SubtitleRGB.black
    /// 배경 상자 불투명도(0~1). 0이면 배경이 없다.
    var backgroundOpacity = 0.6

    static let fontSizeRange = 24.0 ... 120.0
    static let defaultFontName = "AppleSDGothicNeo-Bold"
    /// 상자를 그릴 때 화면 가장자리에서 띄우는 여백(세로는 화면 높이 대비, 가로는 너비 대비).
    static let verticalMarginRatio = 0.06
    static let horizontalMarginRatio = 0.05
}

/// sRGB 색(각 0~1). 도메인이 UI 프레임워크를 쓰지 않도록 따로 둔다.
nonisolated struct SubtitleRGB {
    var red: Double
    var green: Double
    var blue: Double

    static let white = SubtitleRGB(red: 1, green: 1, blue: 1)
    static let black = SubtitleRGB(red: 0, green: 0, blue: 0)
    static let yellow = SubtitleRGB(red: 1, green: 0.85, blue: 0)
}

/// 위·가운데·아래 빠른 위치. 가로 가운데에서 그 높이로 옮긴다(위·아래는 화면 가장자리 여백에 붙는다).
nonisolated enum SubtitlePosition: String, CaseIterable {
    case top
    case middle
    case bottom

    var centerY: Double {
        switch self {
        case .top: 0
        case .middle: 0.5
        case .bottom: 1
        }
    }
}

nonisolated extension SubtitleStyle {
    /// 지금 위치가 빠른 위치 중 하나와 같으면 그 위치.
    var preset: SubtitlePosition? {
        guard centerX == 0.5 else { return nil }
        return SubtitlePosition.allCases.first { $0.centerY == centerY }
    }

    /// 빠른 위치로 옮긴다.
    mutating func move(to position: SubtitlePosition) {
        centerX = 0.5
        centerY = position.centerY
    }

    /// 범위를 벗어난 값은 가장 가까운 값으로 맞춘다.
    mutating func clamp() {
        fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        centerX = Self.unit(centerX)
        centerY = Self.unit(centerY)
        textOpacity = Self.unit(textOpacity)
        backgroundOpacity = Self.unit(backgroundOpacity)
        textColor = textColor.clamped
        backgroundColor = backgroundColor.clamped
        if fontName.isEmpty {
            fontName = Self.defaultFontName
        }
    }

    /// `boxSize` 크기의 자막 상자를 `renderSize` 화면에 놓을 왼쪽 위 좌표(왼쪽 위 원점).
    /// 상자 가운데를 위치 좌표에 두되 가장자리 여백 안으로 맞춘다. 그래서 위(0)·아래(1)는 여백에 붙고, 상자가 화면 밖으로 나가지 않는다.
    func boxOrigin(boxSize: CGSize, renderSize: CGSize) -> CGPoint {
        let marginX = (renderSize.width * Self.horizontalMarginRatio).rounded()
        let marginY = (renderSize.height * Self.verticalMarginRatio).rounded()
        func place(_ center: Double, length: Double, box: Double, margin: Double) -> Double {
            let lower = margin
            let upper = length - margin - box
            guard upper >= lower else { return ((length - box) / 2).rounded() }
            return min(max((center * length - box / 2).rounded(), lower), upper)
        }
        return CGPoint(
            x: place(centerX, length: renderSize.width, box: boxSize.width, margin: marginX),
            y: place(centerY, length: renderSize.height, box: boxSize.height, margin: marginY)
        )
    }

    /// 여백 안쪽 사각형(안전 영역, 왼쪽 위 원점). 자막 상자는 이 안에서만 그려진다. 미리보기 보조선으로 보여준다.
    static func safeArea(in renderSize: CGSize) -> CGRect {
        let marginX = (renderSize.width * horizontalMarginRatio).rounded()
        let marginY = (renderSize.height * verticalMarginRatio).rounded()
        return CGRect(x: marginX, y: marginY, width: renderSize.width - marginX * 2, height: renderSize.height - marginY * 2)
    }

    /// `boxSize` 상자의 가운데가 갈 수 있는 범위(화면 비율). 인스펙터 슬라이더의 0~100%를 이 범위에 맞춰,
    /// 끝까지 끌면 상자가 여백에 닿는다. 상자가 안전 영역보다 크면 가운데 한 점이다.
    static func centerRange(boxSize: CGSize, renderSize: CGSize) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        let area = safeArea(in: renderSize)
        func range(min lower: Double, max upper: Double, box: Double, length: Double) -> ClosedRange<Double> {
            let low = (lower + box / 2) / length
            let high = (upper - box / 2) / length
            return low <= high ? low ... high : 0.5 ... 0.5
        }
        return (
            range(min: area.minX, max: area.maxX, box: boxSize.width, length: renderSize.width),
            range(min: area.minY, max: area.maxY, box: boxSize.height, length: renderSize.height)
        )
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

nonisolated extension SubtitleRGB {
    var clamped: SubtitleRGB {
        SubtitleRGB(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
    }
}

nonisolated extension Subtitle: Identifiable {}
nonisolated extension Subtitle: Equatable {}
nonisolated extension SubtitleStyle: Equatable {}
nonisolated extension SubtitleRGB: Equatable {}

// MARK: - SRT

/// SRT 자막 파일 읽기·쓰기. 타임코드는 `시:분:초,밀리초`다.
nonisolated enum SubtitleFile {
    /// 형식이 맞지 않는 항목은 건너뛴다. 스타일은 기본값이다.
    static func parseSRT(_ text: String) -> [Subtitle] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block -> Subtitle? in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timingIndex].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  let start = parseTimecode(parts[0]),
                  let end = parseTimecode(String(parts[1].prefix(12))),
                  start < end
            else { return nil }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            guard !body.isEmpty else { return nil }
            return Subtitle(id: UUID(), range: CMTimeRange(start: start, end: end), text: body)
        }
    }

    /// 시작 시각 순으로 번호를 매긴다.
    static func makeSRT(_ subtitles: [Subtitle]) -> String {
        subtitles
            .sorted { $0.range.start < $1.range.start }
            .enumerated()
            .map { index, subtitle in
                "\(index + 1)\n\(timecode(subtitle.range.start)) --> \(timecode(subtitle.range.end))\n\(subtitle.text)\n"
            }
            .joined(separator: "\n")
    }

    static func parseTimecode(_ text: String) -> CMTime? {
        let parts = text.replacingOccurrences(of: ".", with: ",").split(separator: ",")
        guard parts.count == 2, let milliseconds = Int(parts[1]) else { return nil }
        let clock = parts[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 3 else { return nil }
        let totalMilliseconds = ((clock[0] * 60 + clock[1]) * 60 + clock[2]) * 1000 + milliseconds
        return CMTime(value: CMTimeValue(totalMilliseconds), timescale: 1000)
    }

    static func timecode(_ time: CMTime) -> String {
        let totalMilliseconds = Int((max(time.seconds, 0) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60000 % 60
        let seconds = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
