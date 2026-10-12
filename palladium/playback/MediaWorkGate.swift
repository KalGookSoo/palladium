import Foundation
import Observation

/// 내보내는 동안 다른 미디어 읽기(파형·필름스트립·손떨림 분석)를 잠시 멈추게 하는 문(#131).
/// 오디오·영상 디코딩 자원을 내보내기에 몰아주기 위해서다. 내보내기가 끝나면 기다리던 읽기가 이어서 시작한다.
@Observable
final class MediaWorkGate {
    static let shared = MediaWorkGate()

    /// 진행 중인 내보내기 수.
    private(set) var exportCount = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    var isExporting: Bool {
        exportCount > 0
    }

    func beginExport() {
        exportCount += 1
    }

    func endExport() {
        exportCount = max(exportCount - 1, 0)
        guard exportCount == 0 else { return }
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    /// 내보내는 중이면 끝날 때까지 기다린다.
    func waitUntilIdle() async {
        guard isExporting else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
