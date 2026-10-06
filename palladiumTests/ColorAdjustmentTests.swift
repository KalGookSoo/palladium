import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 기본 색보정(밝기·대비·채도, #61).
@MainActor
struct ColorAdjustmentTests {
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

    @Test("기본값은 원본 그대로(밝기 0, 대비 1, 채도 1)이고, 범위 밖 값은 범위 안으로 맞춘다")
    func defaultsAndClamping() {
        let adjustment = ColorAdjustment()
        #expect(adjustment.brightness == 0 && adjustment.contrast == 1 && adjustment.saturation == 1)
        #expect(adjustment.isDefault)

        var wild = ColorAdjustment(brightness: 3, contrast: 0, saturation: -1)
        wild.clamp()
        #expect(wild == ColorAdjustment(brightness: 0.5, contrast: 0.5, saturation: 0))
        #expect(!wild.isDefault)
    }

    @Test("여러 클립에 같은 값을 넣고, 나누기·복사·붙여넣기에 값이 따라가며, 실행 취소 한 번으로 되돌리고, 저장된다")
    func setColorAdjustmentCommand() throws {
        let editor = try makeEditor()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let clips = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips)
        let ids: Set<Clip.ID> = [clips[0].id, clips[1].id]
        let before = editor.project
        let adjustment = ColorAdjustment(brightness: 0.2, contrast: 1.3, saturation: 0)

        undoManager.beginUndoGrouping()
        editor.setColorAdjustment(ColorAdjustment(brightness: 0.2, contrast: 9, saturation: 0), for: ids)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "색보정")
        for id in ids {
            #expect(editor.currentSequence.clip(id: id)?.colorAdjustment == ColorAdjustment(brightness: 0.2, contrast: 1.5, saturation: 0))
        }
        undoManager.undo()
        #expect(editor.project == before)

        undoManager.beginUndoGrouping()
        editor.setColorAdjustment(adjustment, for: [clips[0].id])
        editor.splitClips([clips[0].id], at: CMTime(value: 2, timescale: 1))
        undoManager.endUndoGrouping()
        let pieces = editor.currentSequence.tracks.flatMap(\.clips).filter { $0.assetID == clips[0].assetID }
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.colorAdjustment == adjustment })

        editor.copyClips([clips[0].id])
        // 묶음 밖에서 실행 취소를 남기면 예외가 나 테스트가 멈추므로 붙여넣기도 묶는다.
        undoManager.beginUndoGrouping()
        let pasted = editor.pasteClips(at: editor.currentSequence.duration)
        undoManager.endUndoGrouping()
        guard case let .clips(pastedIDs) = pasted else {
            Issue.record("붙여넣지 못함")
            return
        }
        #expect(pastedIDs.allSatisfy { editor.currentSequence.clip(id: $0)?.colorAdjustment == adjustment })

        try editor.save()
        #expect(try repository.project(id: editor.project.id) == editor.project)
    }

    // MARK: - Helpers

    private func makeEditor() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }
}
