import Foundation
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

    @Test("폴더의 원본은 폴더에 담긴 순서대로 돌려준다")
    func assetsInFolderFollowFolderOrder() {
        let project = SampleData.project
        let folderAssets = project.assets(in: SampleData.footageFolder)
        #expect(folderAssets == [SampleData.introVideo, SampleData.bRollVideo])
    }

    @Test("프로젝트에 없는 원본 ID는 폴더 조회에서 건너뛴다")
    func assetsInFolderSkipsUnknownIDs() {
        let project = SampleData.project
        let folder = MediaFolder(id: UUID(), name: "섞인 폴더", assetIDs: [UUID(), SampleData.introVideo.id])
        #expect(project.assets(in: folder) == [SampleData.introVideo])
    }

    @Test("어느 폴더에도 없는 원본만 분류 안 됨으로 본다")
    func unfiledAssetsExcludeFiledAssets() {
        #expect(SampleData.project.unfiledAssets == [SampleData.backgroundMusic])
    }

    @Test("새 프로젝트 이름의 앞뒤 공백은 지우고, 비어 있으면 기본 이름을 쓴다")
    func newProjectNameIsNormalized() {
        #expect(Project.makeNew(name: "  여행 브이로그 ").name == "여행 브이로그")
        #expect(Project.makeNew(name: "   ").name == Project.untitledName)
    }

    @Test("요약은 원본·시퀀스 개수를 담는다")
    func summaryCountsAssetsAndSequences() {
        let date = Date(timeIntervalSince1970: 0)
        let summary = SampleData.project.summary(createdAt: date, modifiedAt: date)
        #expect(summary.assetCount == 3)
        #expect(summary.sequenceCount == 1)
        #expect(summary.id == SampleData.project.id)
    }
}
