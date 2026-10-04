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

struct ProjectSequenceCommandTests {
    @Test("시퀀스를 추가하면 끝에 빈 시퀀스가 생기고, 이름이 비어 있으면 '시퀀스 N'이다")
    func addSequence() {
        var project = Project.makeNew(name: "프로젝트")
        let namedID = project.addSequence(named: "  하이라이트 ")
        project.addSequence(named: "")

        #expect(project.sequences.map(\.name) == ["시퀀스 1", "하이라이트", "시퀀스 3"])
        #expect(project.sequences[1].id == namedID)
        #expect(project.sequences[1].tracks.isEmpty)
    }

    @Test("시퀀스 이름은 공백을 빼고 바꾸며, 비어 있으면 바꾸지 않는다")
    func renameSequence() {
        var project = Project.makeNew(name: "프로젝트")
        let sequenceID = project.sequences[0].id
        project.renameSequence(sequenceID, to: " 통합본 ")
        project.renameSequence(sequenceID, to: "  ")
        #expect(project.sequences[0].name == "통합본")
    }

    @Test("시퀀스를 지워도 원본은 남고, 마지막 남은 시퀀스는 지우지 않는다")
    func deleteSequence() {
        var project = SampleData.project
        let firstID = project.sequences[0].id
        let addedID = project.addSequence(named: "하이라이트")

        project.deleteSequence(firstID)
        project.deleteSequence(addedID)

        #expect(project.sequences.map(\.id) == [addedID])
        #expect(project.assets == SampleData.project.assets)
    }
}

struct ProjectFolderCommandTests {
    @Test("폴더를 만들고 이름을 바꾸며, 이름이 비어 있으면 '새 폴더'이고 빈 이름으로는 바꾸지 않는다")
    func addAndRenameFolder() {
        var project = Project.makeNew(name: "프로젝트")
        let folderID = project.addFolder(named: "")
        project.renameFolder(folderID, to: " 촬영본 ")
        project.renameFolder(folderID, to: " ")
        #expect(project.folders.map(\.name) == ["촬영본"])
    }

    @Test("원본은 한 폴더에만 속하고, 폴더로 옮기면 다른 폴더에서 빠지며, nil이면 분류 안 됨으로 돌아간다")
    func moveAssetsBetweenFolders() {
        var project = SampleData.project
        let footageID = SampleData.footageFolder.id
        let musicID = project.addFolder(named: "음악")

        project.moveAssets([SampleData.introVideo.id], toFolder: musicID)
        #expect(project.folders.map(\.assetIDs) == [[SampleData.bRollVideo.id], [SampleData.introVideo.id]])

        project.moveAssets([SampleData.introVideo.id], toFolder: nil)
        #expect(project.unfiledAssets.map(\.id).contains(SampleData.introVideo.id))
        #expect(project.folders.first { $0.id == footageID }?.assetIDs == [SampleData.bRollVideo.id])
    }

    @Test("같은 폴더 안에서 다른 원본 앞으로 옮기면 순서가 바뀐다")
    func reorderWithinFolder() {
        var project = SampleData.project
        project.moveAssets([SampleData.bRollVideo.id], toFolder: SampleData.footageFolder.id, before: SampleData.introVideo.id)
        #expect(project.folders[0].assetIDs == [SampleData.bRollVideo.id, SampleData.introVideo.id])
    }

    @Test("폴더를 지워도 안의 원본은 프로젝트에 남아 분류 안 됨이 된다")
    func deleteFolderKeepsAssets() {
        var project = SampleData.project
        project.deleteFolder(SampleData.footageFolder.id)
        #expect(project.folders.isEmpty)
        #expect(project.assets == SampleData.project.assets)
        #expect(project.unfiledAssets.count == project.assets.count)
    }
}
