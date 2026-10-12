import Foundation

/// 내보내기 진행 시간 계산(#130). 지난 시간과 진행률로 남은 시간을 어림하고, 진행률이 오래 그대로면 멈춘 것으로 본다.
nonisolated enum ExportTiming {
    /// 진행률이 이만큼 바뀌지 않으면 "응답이 없습니다"를 보여준다.
    static let stallInterval: TimeInterval = 30
    /// 진행률이 이보다 작으면 남은 시간을 어림하지 않는다(처음엔 들쭉날쭉하다).
    static let minimumProgressForEstimate = 0.02

    /// 남은 시간(초). 어림할 수 없으면 `nil`.
    static func remaining(elapsed: TimeInterval, progress: Double) -> TimeInterval? {
        guard progress >= minimumProgressForEstimate, progress < 1, elapsed > 0 else { return nil }
        return elapsed * (1 - progress) / progress
    }

    /// 마지막으로 진행률이 바뀐 뒤 `stallInterval` 넘게 지났는지.
    static func isStalled(sinceLastProgress interval: TimeInterval) -> Bool {
        interval >= stallInterval
    }

    /// "1:05"·"1:02:03"처럼 보일 시간 글자.
    static func label(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
