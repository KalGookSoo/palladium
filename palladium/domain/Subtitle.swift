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
nonisolated struct SubtitleStyle {
    var fontSize = 54.0
    var position = SubtitlePosition.bottom
    var color = SubtitleColor.white
    /// 글자 뒤에 반투명 검은 상자를 깔아 밝은 화면에서도 읽히게 한다.
    var hasBackground = true

    static let fontSizeRange = 24.0 ... 120.0
}

nonisolated enum SubtitlePosition: String, CaseIterable {
    case top
    case middle
    case bottom
}

nonisolated enum SubtitleColor: String, CaseIterable {
    case white
    case yellow
}

nonisolated extension Subtitle: Identifiable {}
nonisolated extension Subtitle: Equatable {}
nonisolated extension SubtitleStyle: Equatable {}

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
