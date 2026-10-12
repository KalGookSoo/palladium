import Foundation
@testable import palladium
import SwiftData
import Testing

/// 미디어 패널의 Finder식 명령(#110 선택 항목으로 새 폴더, #116 제자리 복제).
/// 샘플: "촬영본" 폴더에 인트로·B컷, 맨 위에 배경음악.
@MainActor
struct MediaPanelFinderTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // 자동 저장 타이머가 테스트가 끝나 사라진 컨테이너에 불리면 앱이 멈추므로 끈다.
        container.mainContext.autosaveEnabled = false
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    @Test("선택 항목으로 새 폴더는 고른 원본들을 담은 새 폴더를 그 원본이 있던 폴더 안에 만들고, 실행 취소 한 번으로 돌아온다")
    func newFolderWithAssets() throws {
        let editor = try makeEditor()
        let footage = try #require(editor.project.folders.first)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let folderID = try #require(editor.addFolder(containing: [SampleData.introVideo.id, SampleData.bRollVideo.id], folderIDs: []))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "선택 항목으로 새 폴더")

        let newFolder = try #require(editor.project.folders.first { $0.id == folderID })
        #expect(newFolder.parentID == footage.id)
        #expect(Set(newFolder.assetIDs) == [SampleData.introVideo.id, SampleData.bRollVideo.id])
        #expect(editor.project.folders.first { $0.id == footage.id }?.assetIDs.isEmpty == true)

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("폴더를 고르면 새 폴더는 그 폴더의 부모(맨 위)에 생기고 고른 폴더가 그 안으로 들어간다. 맨 위 원본도 함께 담는다")
    func newFolderWithFolders() throws {
        let editor = try makeEditor()
        let footage = try #require(editor.project.folders.first)
        let folderID = try #require(editor.addFolder(containing: [SampleData.backgroundMusic.id], folderIDs: [footage.id]))
        let newFolder = try #require(editor.project.folders.first { $0.id == folderID })
        #expect(newFolder.parentID == nil)
        #expect(editor.project.folders.first { $0.id == footage.id }?.parentID == folderID)
        #expect(newFolder.assetIDs == [SampleData.backgroundMusic.id])
        #expect(editor.addFolder(containing: [], folderIDs: []) == nil)
    }

    @Test("제자리 복제는 원본마다 같은 폴더에 사본을 만들고(이름 뒤 (1)), 실행 취소 한 번으로 돌아온다")
    func duplicateInPlace() throws {
        let editor = try makeEditor()
        let footage = try #require(editor.project.folders.first)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let copies = editor.duplicateAssetsInPlace([SampleData.introVideo.id, SampleData.backgroundMusic.id])
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "원본 복제")
        #expect(copies.count == 2)

        let introCopy = try #require(editor.asset(id: copies[0]))
        #expect(introCopy.name == "intro (1).mov" && introCopy.sourceURL == SampleData.introVideo.sourceURL)
        #expect(editor.project.folders.first { $0.id == footage.id }?.assetIDs.contains(copies[0]) == true)
        // 맨 위 원본의 사본은 맨 위에 남는다.
        #expect(!editor.project.folders.contains { $0.assetIDs.contains(copies[1]) })

        undoManager.undo()
        #expect(editor.project == before)
    }

    private func makeEditor() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }
}
