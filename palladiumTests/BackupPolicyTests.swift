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
