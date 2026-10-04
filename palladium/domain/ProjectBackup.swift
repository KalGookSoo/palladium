import Foundation

/// 비정상 종료에 대비해 저장하지 않은 변경을 담아 둔 백업본.
nonisolated struct ProjectBackup {
    let project: Project
    let backedUpAt: Date
}

nonisolated extension ProjectBackup: Equatable {}

/// 저장하지 않은 변경을 백업본에 쓰는 규칙.
nonisolated enum BackupPolicy {
    /// 환경설정(#19)에서 조정할 수 있게 되기 전까지의 기본 백업 간격.
    static let defaultInterval: Duration = .seconds(60)
    /// 환경설정에서 고를 수 있는 백업 간격(초). 비정상 종료 뒤 복구를 지키려고 "끔"은 두지 않는다.
    static let intervalChoicesInSeconds = [30, 60, 120, 300, 600]

    /// 저장된 값이 없거나(0) 고를 수 없는 값이면 기본 간격을 쓴다.
    static func interval(fromStoredSeconds seconds: Int) -> Duration {
        intervalChoicesInSeconds.contains(seconds) ? .seconds(seconds) : defaultInterval
    }

    /// 저장하지 않은 변경이 있고, 마지막으로 쓴 백업본 이후 또 바뀌었을 때만 쓴다.
    static func shouldWriteBackup(current: Project, saved: Project, lastBackedUp: Project?) -> Bool {
        current != saved && current != lastBackedUp
    }
}
