import Foundation

/// 비정상 종료에 대비해 저장하지 않은 변경을 담아 둔 백업본.
nonisolated struct ProjectBackup {
    let project: Project
    let backedUpAt: Date
}

extension ProjectBackup: Equatable {}

/// 저장하지 않은 변경을 백업본에 쓰는 규칙.
nonisolated enum BackupPolicy {
    /// 환경설정(#19)에서 조정할 수 있게 되기 전까지의 기본 백업 간격.
    static let defaultInterval: Duration = .seconds(60)

    /// 저장하지 않은 변경이 있고, 마지막으로 쓴 백업본 이후 또 바뀌었을 때만 쓴다.
    static func shouldWriteBackup(current: Project, saved: Project, lastBackedUp: Project?) -> Bool {
        current != saved && current != lastBackedUp
    }
}
