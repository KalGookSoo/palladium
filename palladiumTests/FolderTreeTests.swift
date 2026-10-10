import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 미디어 패널 폴더 트리(#93): 하위 폴더, 폴더 옮기기·지우기, 트리 순서, 저장.
@MainActor
struct FolderTreeTests {
    private func asset(_ name: String) -> MediaAsset {
        MediaAsset(id: UUID(), name: name, sourceURL: URL(filePath: "/tmp/\(name)"), kind: .video, duration: CMTime(value: 1, timescale: 1))
    }

    private func emptyProject() throws -> Project {
        try #require(Project(name: "트리", assets: [], sequences: [EditSequence(id: UUID(), name: "시퀀스", tracks: [])]))
    }

    @Test("폴더 안에 폴더를 만들고, 트리는 하위 폴더를 먼저 각각 이름순으로 펼치며, 가장 깊은 깊이를 안다")
    func nestedFoldersAndTreeOrder() throws {
        var project = try emptyProject()
        let shoot = project.addFolder(named: "촬영본")
        let day2 = project.addFolder(named: "2일차", in: shoot)
        let day1 = project.addFolder(named: "1일차", in: shoot)
        let raw = project.addFolder(named: "원본", in: day1)
        let audio = project.addFolder(named: "오디오")
        // 없는 폴더 안에 만들면 맨 위에 만든다.
        let orphan = project.addFolder(named: "고아", in: UUID())

        #expect(project.folderTree.map(\.folder.id) == [orphan, audio, shoot, day1, raw, day2])
        #expect(project.folderTree.map(\.depth) == [0, 0, 0, 1, 2, 1])
        #expect(project.subfolders(of: shoot).map(\.id) == [day1, day2])
        #expect(project.maximumFolderDepth == 3)
        #expect(project.folderPath(raw) == "촬영본 / 1일차 / 원본")
    }

    @Test("폴더는 자기 자신이나 자기 아래 폴더로 옮길 수 없고, 다른 폴더 안이나 맨 위로는 옮긴다")
    func moveFolderRejectsCycles() throws {
        var project = try emptyProject()
        let a = project.addFolder(named: "A")
        let b = project.addFolder(named: "B", in: a)
        let c = project.addFolder(named: "C", in: b)
        let other = project.addFolder(named: "다른")

        let intoSelf = project.moveFolder(a, into: a)
        let intoDescendant = project.moveFolder(a, into: c)
        #expect(!intoSelf)
        #expect(!intoDescendant)
        #expect(project.folders.first { $0.id == a }?.parentID == nil)

        let intoOther = project.moveFolder(b, into: other)
        #expect(intoOther)
        #expect(project.folderPath(c) == "다른 / B / C")
        let toRoot = project.moveFolder(b, into: nil)
        #expect(toRoot)
        #expect(project.folders.first { $0.id == b }?.parentID == nil)
        let intoMissing = project.moveFolder(b, into: UUID())
        #expect(!intoMissing)
    }

    @Test("폴더를 지우면 안의 원본과 하위 폴더는 한 단계 위로 올라간다")
    func deleteFolderLiftsContents() throws {
        var project = try emptyProject()
        let clipA = asset("a.mov")
        let clipB = asset("b.mov")
        project.assets = [clipA, clipB]
        let top = project.addFolder(named: "위")
        let middle = project.addFolder(named: "가운데", in: top)
        let bottom = project.addFolder(named: "아래", in: middle)
        project.moveAssets([clipA.id], toFolder: middle)
        project.moveAssets([clipB.id], toFolder: top)

        project.deleteFolder(middle)
        #expect(project.folders.first { $0.id == bottom }?.parentID == top)
        #expect(try Set(project.assets(in: #require(project.folders.first { $0.id == top })).map(\.id)) == [clipA.id, clipB.id])

        // 맨 위 폴더를 지우면 원본은 맨 위(분류 안 됨)로, 하위 폴더는 맨 위 폴더가 된다.
        project.deleteFolder(top)
        #expect(project.folders.first { $0.id == bottom }?.parentID == nil)
        #expect(Set(project.unfiledAssets.map(\.id)) == [clipA.id, clipB.id])
    }

    @Test("검색 중에는 그 아래 어딘가에 맞는 원본이 있는 폴더만 보이고, 목록 순서는 트리를 펼친 순서다")
    func filteringAndListOrder() throws {
        var project = try emptyProject()
        let deep = asset("인터뷰.mov")
        let top = asset("b-roll.mov")
        let loose = asset("음악.m4a")
        project.assets = [deep, top, loose]
        let parent = project.addFolder(named: "촬영본")
        let child = project.addFolder(named: "1일차", in: parent)
        let empty = project.addFolder(named: "빈 폴더")
        project.moveAssets([deep.id], toFolder: child)
        project.moveAssets([top.id], toFolder: parent)

        #expect(project.folderContainsAsset(parent) { $0.name.contains("인터뷰") })
        #expect(project.folderContainsAsset(child) { $0.name.contains("인터뷰") })
        #expect(!project.folderContainsAsset(empty) { _ in true })
        #expect(project.assetListOrder == [top.id, deep.id, loose.id])
        #expect(project.folderIDs(containing: deep.id) == [child, parent])
        #expect(project.folderIDs(containing: loose.id) == [])
    }

    @Test("폴더 옮기기는 편집기 커맨드로 실행 취소 한 번에 돌아오고, 안 되는 이동은 편집을 남기지 않는다")
    func editorMoveFolderUndo() throws {
        let container = try ModelContainer(for: ProjectRecord.self, ProjectBackupRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let editor = try ProjectEditor(project: repository.createProject(named: "트리"), repository: repository)
        let a = editor.addFolder(named: "A")
        let b = editor.addFolder(named: "B", in: a)
        let before = editor.project
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager

        editor.moveFolder(a, into: b)
        #expect(editor.project == before)
        #expect(!undoManager.canUndo)

        undoManager.beginUndoGrouping()
        editor.moveFolder(b, into: nil)
        undoManager.endUndoGrouping()
        #expect(editor.project.folders.first { $0.id == b }?.parentID == nil)
        #expect(undoManager.undoActionName == "폴더 이동")
        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("하위 폴더 관계는 저장했다가 그대로 불러온다")
    func persistsParent() throws {
        let container = try ModelContainer(for: ProjectRecord.self, ProjectBackupRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let editor = try ProjectEditor(project: repository.createProject(named: "트리"), repository: repository)
        let parent = editor.addFolder(named: "촬영본")
        let child = editor.addFolder(named: "1일차", in: parent)
        try editor.save()

        let loaded = try #require(try repository.project(id: editor.project.id))
        #expect(loaded.folders.first { $0.id == child }?.parentID == parent)
        #expect(loaded.folders.first { $0.id == parent }?.parentID == nil)
    }

    @Test("사이드바 최대 폭은 폴더가 한 단계 깊어질 때마다 들여쓰기만큼 늘고 상한에서 멈춘다")
    func sidebarWidthFollowsDepth() {
        #expect(MainWindowMetrics.sidebarMaxWidth(folderDepth: 0) == 320)
        #expect(MainWindowMetrics.sidebarMaxWidth(folderDepth: 1) == 320)
        #expect(MainWindowMetrics.sidebarMaxWidth(folderDepth: 3) == 360)
        #expect(MainWindowMetrics.sidebarMaxWidth(folderDepth: 50) == MainWindowMetrics.sidebarMaxWidthLimit)
    }
}
