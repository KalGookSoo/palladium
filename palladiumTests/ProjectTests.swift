@testable import palladium
import Testing

struct ProjectTests {
    @Test("시퀀스가 하나도 없으면 프로젝트를 만들 수 없다")
    func rejectsEmptySequences() {
        let project = Project(name: "빈 프로젝트", assets: [], sequences: [])
        #expect(project == nil)
    }

    @Test("새 프로젝트는 트랙 없는 시퀀스 하나로 시작한다")
    func newProjectStartsWithOneEmptySequence() {
        let project = Project.makeNew(name: "새 프로젝트")
        #expect(project.name == "새 프로젝트")
        #expect(project.assets.isEmpty)
        #expect(project.sequences.count == 1)
        #expect(project.sequences.first?.name == "시퀀스 1")
        #expect(project.sequences.first?.tracks.isEmpty == true)
    }
}
