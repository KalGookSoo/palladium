@testable import palladium
import Testing

struct BackupPolicyTests {
    private let saved = Project.makeNew(name: "저장본")

    @Test("저장하지 않은 변경이 없으면 백업하지 않는다")
    func noUnsavedChangesMeansNoBackup() {
        #expect(!BackupPolicy.shouldWriteBackup(current: saved, saved: saved, lastBackedUp: nil))
    }

    @Test("저장하지 않은 변경이 있고 아직 백업하지 않았으면 백업한다")
    func unsavedChangesAreBackedUp() {
        var edited = saved
        edited.name = "고친 이름"
        #expect(BackupPolicy.shouldWriteBackup(current: edited, saved: saved, lastBackedUp: nil))
    }

    @Test("마지막 백업 이후 바뀐 것이 없으면 다시 쓰지 않는다")
    func unchangedSinceLastBackupIsSkipped() {
        var edited = saved
        edited.name = "고친 이름"
        #expect(!BackupPolicy.shouldWriteBackup(current: edited, saved: saved, lastBackedUp: edited))
    }
}

struct BackupIntervalTests {
    @Test("저장된 간격이 고를 수 있는 값이면 그대로 쓰고, 없거나 엉뚱한 값이면 기본 1분을 쓴다")
    func storedIntervalFallsBackToDefault() {
        #expect(BackupPolicy.interval(fromStoredSeconds: 300) == .seconds(300))
        #expect(BackupPolicy.interval(fromStoredSeconds: 0) == BackupPolicy.defaultInterval)
        #expect(BackupPolicy.interval(fromStoredSeconds: 7) == BackupPolicy.defaultInterval)
    }
}
