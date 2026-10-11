import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 미디어 패널 잘라내기·복사(사본)·붙여넣기(#104).
@MainActor
struct AssetClipboardTests {
    private func asset(_ name: String) -> MediaAsset {
        MediaAsset(id: UUID(), name: name, sourceURL: URL(filePath: "/tmp/\(name)"), kind: .video, duration: CMTime(value: 10, timescale: 1))
    }

    @Test("클립보드 글자는 복사·잘라내기와 원본 ID를 담고, 미디어 패널에서 담은 글자가 아니면 읽지 않는다")
    func payload() {
        let ids = [UUID(), UUID()]
        let copied = AssetClipboardPayload.decode(AssetClipboardPayload.encode(ids, isCut: false))
        #expect(copied?.assetIDs == ids)
        #expect(copied?.isCut == false)
        #expect(AssetClipboardPayload.decode(AssetClipboardPayload.encode(ids, isCut: true))?.isCut == true)
        #expect(AssetClipboardPayload.decode(AssetDragPayload.encode(ids)) == nil)
        #expect(AssetClipboardPayload.decode("palladium-assets-copy") == nil)
    }

    @Test("사본은 같은 파일을 가리키고 구간·크롭·레이블·태그가 같으며, 이름이 겹치면 (1)·(2)를 붙여 고른 폴더에 들어간다")
    func duplicates() throws {
        var source = asset("윈드밀1.mov")
        source.colorLabel = .green
        source.tags = ["B컷"]
        var project = try #require(Project(name: "복사", assets: [source], sequences: [EditSequence(id: UUID(), name: "시퀀스", tracks: [])]))
        let folder = project.addFolder(named: "사본")

        let first = project.duplicateAssets([source.id], toFolder: folder)
        let second = project.duplicateAssets([source.id], toFolder: nil)
        let copy = try #require(project.assets.first { $0.id == first.first })
        let copy2 = try #require(project.assets.first { $0.id == second.first })

        #expect(copy.name == "윈드밀1 (1).mov")
        #expect(copy2.name == "윈드밀1 (2).mov")
        #expect(copy.sourceURL == source.sourceURL)
        #expect(copy.colorLabel == .green)
        #expect(copy.tags == ["B컷"])
        #expect(copy.mediaKey == source.mediaKey)
        #expect(project.folders[0].assetIDs == [copy.id])
        #expect(project.unfiledAssets.map(\.id).contains(copy2.id))
        #expect(project.assets.count == 3)
        // 원본 항목은 그대로다.
        #expect(project.assets.first { $0.id == source.id } == source)
        #expect(project.copiedAssetName(for: "새 이름.mov", taken: ["다른.mov"]) == "새 이름.mov")
    }

    @Test("붙여넣기(사본 만들기)는 편집기 커맨드로 실행 취소 한 번에 사라진다")
    func editorUndo() throws {
        let container = try ModelContainer(for: ProjectRecord.self, ProjectBackupRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let editor = try ProjectEditor(project: repository.createProject(named: "복사"), repository: repository)
        let source = asset("a.mov")
        editor.applyDebugChange { $0.assets = [source] }
        let before = editor.project
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager

        undoManager.beginUndoGrouping()
        let copied = editor.duplicateAssets([source.id, source.id], toFolder: nil)
        undoManager.endUndoGrouping()
        #expect(copied.count == 2)
        #expect(editor.project.assets.map(\.name) == ["a.mov", "a (1).mov", "a (2).mov"])
        #expect(undoManager.undoActionName == "원본 붙여넣기")
        undoManager.undo()
        #expect(editor.project == before)
    }
}
