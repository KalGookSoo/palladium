import CoreMedia
import Foundation
import OSLog

/// 합성기가 그리지 못한 프레임 기록(#130). 합성 하나(미리보기·내보내기)에 하나씩 두고, 합성기가 실패를 적으면 내보내기가 실패 안내에 쓴다.
/// 합성기는 AVFoundation이 여러 스레드에서 부르므로 잠금으로 지킨다.
final nonisolated class CompositionDiagnostics: @unchecked Sendable {
    struct Failure: Equatable {
        /// 합성(시퀀스) 시각(초).
        let time: Double
        /// 그리지 못한 클립(원본) 이름. 모르면 `nil`.
        let clipName: String?
        let reason: String
    }

    private let lock = NSLock()
    private var failures: [Failure] = []
    private var count = 0
    /// 기록해 둘 실패 수. 넘으면 수만 센다.
    private static let maximumStored = 20

    func record(time: CMTime, clipName: String?, reason: String) {
        let failure = Failure(time: time.seconds, clipName: clipName, reason: reason)
        let isFirst = lock.withLock {
            count += 1
            if failures.count < Self.maximumStored {
                failures.append(failure)
            }
            return count == 1
        }
        if isFirst {
            Logger.playback.error("합성 실패: \(reason, privacy: .public) \(clipName ?? "", privacy: .public) \(time.seconds)")
        }
    }

    var failureCount: Int {
        lock.withLock { count }
    }

    var recordedFailures: [Failure] {
        lock.withLock { failures }
    }

    /// 사람이 읽을 요약. 실패가 없으면 `nil`. 예: "프레임 3개를 그리지 못했습니다 — 0:12.3 '인트로'(원본 프레임을 읽지 못함), …"
    var summary: String? {
        let count = failureCount
        let failures = recordedFailures
        guard count > 0 else { return nil }
        let samples = failures.prefix(3).map { failure in
            let name = failure.clipName.map { " '\($0)'" } ?? ""
            return "\(Self.timeLabel(failure.time))\(name)(\(failure.reason))"
        }
        let more = count > samples.count ? " 외 \(count - samples.count)개" : ""
        return "프레임 \(count)개를 그리지 못했습니다 — \(samples.joined(separator: ", "))\(more)"
    }

    /// "1:02.5"(분:초.소수 첫째 자리).
    static func timeLabel(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded(.down))
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}
