import AVFoundation
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 편집기는 View 없이 커맨드·쿼리만으로 프로젝트를 편집할 수 있어야 한다(MCP 대비).
@MainActor
struct ProjectEditorTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        var clock = Date(timeIntervalSince1970: 0)
        repository = SwiftDataProjectRepository(modelContext: container.mainContext) {
            clock = clock.addingTimeInterval(60)
            return clock
        }
    }

    @Test("원본 이름·색상 레이블·태그를 바꾸면 저장하지 않은 변경이 된다")
    func assetCommandsMakeUnsavedChanges() throws {
        let editor = try makeEditorWithSampleContent()
        let introID = SampleData.introVideo.id
        let bRollID = SampleData.bRollVideo.id

        editor.renameAsset(introID, to: "오프닝")
        editor.setColorLabel(.red, for: [introID, bRollID])
        editor.setTags(from: "인터뷰, B컷", for: bRollID)

        #expect(editor.asset(id: introID)?.name == "오프닝")
        #expect(editor.asset(id: introID)?.colorLabel == .red)
        #expect(editor.asset(id: bRollID)?.colorLabel == .red)
        #expect(editor.asset(id: bRollID)?.tags == ["인터뷰", "B컷"])
        #expect(editor.assets(matching: MediaFilter(query: "인터뷰")).map(\.id) == [bRollID])
        #expect(editor.hasUnsavedChanges)
    }

    @Test("저장하면 저장소에 반영되고 저장하지 않은 변경이 없어지며 백업본도 지워진다")
    func saveClearsUnsavedChangesAndBackup() throws {
        let editor = try makeEditorWithSampleContent()
        editor.renameAsset(SampleData.introVideo.id, to: "오프닝")
        try editor.writeBackupIfNeeded()
        #expect(try repository.recoverableBackup(for: editor.project.id) != nil)

        try editor.save()

        #expect(!editor.hasUnsavedChanges)
        #expect(try repository.project(id: editor.project.id) == editor.project)
        #expect(try repository.recoverableBackup(for: editor.project.id) == nil)
    }

    @Test("저장하지 않은 변경이 없거나 마지막 백업 이후 바뀌지 않았으면 백업본을 쓰지 않는다")
    func backupIsWrittenOnlyWhenNeeded() throws {
        let editor = try makeEditorWithSampleContent()
        try editor.writeBackupIfNeeded()
        #expect(try repository.recoverableBackup(for: editor.project.id) == nil)

        editor.renameAsset(SampleData.introVideo.id, to: "오프닝")
        try editor.writeBackupIfNeeded()
        let firstBackup = try #require(try repository.recoverableBackup(for: editor.project.id))

        try editor.writeBackupIfNeeded()
        #expect(try repository.recoverableBackup(for: editor.project.id) == firstBackup)
    }

    @Test("변경을 버리면 백업본이 지워진다")
    func discardBackupDeletesBackup() throws {
        let editor = try makeEditorWithSampleContent()
        editor.renameAsset(SampleData.introVideo.id, to: "오프닝")
        try editor.writeBackupIfNeeded()

        editor.discardBackup()

        #expect(try repository.recoverableBackup(for: editor.project.id) == nil)
    }

    @Test("복구한 내용으로 열면 저장하지 않은 변경 상태로 시작한다")
    func recoveredContentStartsAsUnsavedChange() throws {
        let saved = try repository.createProject(named: "샘플")
        var recovered = saved
        recovered.name = "복구한 이름"

        let editor = ProjectEditor(project: saved, recoveredContent: recovered, repository: repository)

        #expect(editor.project == recovered)
        #expect(editor.hasUnsavedChanges)
    }

    @Test("가져온 원본은 프로젝트에 추가되고, 이미 있는 파일은 건너뛴다")
    func importMediaAddsAssets() async throws {
        let editor = try makeEditorWithSampleContent()
        let url = try makeSilentAudio()

        let first = await editor.importMedia(from: [url])
        let second = await editor.importMedia(from: [url])

        let importedID = try #require(first.imported.first?.id)
        #expect(editor.asset(id: importedID)?.name == url.lastPathComponent)
        #expect(second.imported.isEmpty)
        #expect(second.duplicateIDs == [importedID])
        #expect(editor.project.assets.count == SampleData.project.assets.count + 1)
    }

    @Test("빈 시퀀스에 원본을 놓으면 맞는 종류의 트랙이 생기고 원본 길이의 클립이 놓인다")
    func placeAssetCreatesTrack() throws {
        let editor = try ProjectEditor(project: repository.createProject(named: "빈 프로젝트"), repository: repository)
        editor.applyDebugChange { $0.assets = [SampleData.introVideo, SampleData.backgroundMusic] }

        let videoClipID = try #require(editor.placeAsset(SampleData.introVideo.id, onTrack: nil, at: .zero))
        // 영상 트랙에 오디오를 놓으려 하면 오디오 트랙을 새로 만든다.
        let videoTrackID = try #require(editor.project.sequences[0].tracks.first?.id)
        editor.placeAsset(SampleData.backgroundMusic.id, onTrack: videoTrackID, at: .zero)

        let tracks = editor.project.sequences[0].tracks
        #expect(tracks.map(\.kind) == [.video, .audio])
        #expect(tracks[0].clips.map(\.id) == [videoClipID])
        #expect(tracks[0].clips[0].sourceRange.duration == SampleData.introVideo.duration)
    }

    @Test("트랙 밖에 놓아도 같은 종류 트랙이 있으면 새 트랙을 만들지 않고, 트랙은 직접 추가·삭제한다")
    func tracksAreAddedOnlyOnRequest() throws {
        let editor = try makeEditorWithSampleContent()
        let trackCount = editor.currentSequence.tracks.count

        editor.placeAsset(SampleData.introVideo.id, onTrack: nil, at: .zero)
        #expect(editor.currentSequence.tracks.count == trackCount)

        let newTrackID = editor.addTrack(kind: .video)
        #expect(editor.currentSequence.tracks.first?.id == newTrackID)
        editor.deleteTrack(newTrackID)
        #expect(editor.currentSequence.tracks.count == trackCount)
    }

    @Test("편집 커맨드는 실행 취소와 다시 실행으로 되돌릴 수 있다")
    func editsCanBeUndoneAndRedone() throws {
        let editor = try makeEditorWithSampleContent()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let videoTrackID = try #require(editor.project.sequences[0].tracks.first { $0.kind == .video }?.id)
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.placeAsset(SampleData.bRollVideo.id, onTrack: videoTrackID, at: .zero)
        undoManager.endUndoGrouping()
        let after = editor.project
        #expect(after != before)
        #expect(undoManager.undoActionName == "클립 배치")

        undoManager.undo()
        #expect(editor.project == before)
        undoManager.redo()
        #expect(editor.project == after)
    }

    @Test("클립 이동·삭제·자르기는 현재 시퀀스를 바꾸고 각각 실행 취소 이름을 남긴다")
    func clipCommands() throws {
        let editor = try makeEditorWithSampleContent()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let videoTrack = try #require(editor.project.sequences[0].tracks.first { $0.kind == .video })
        let firstClipID = videoTrack.clips[0].id

        undoManager.beginUndoGrouping()
        editor.splitClips([firstClipID], at: CMTime(value: 1, timescale: 1))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "자르기")
        #expect(editor.project.sequences[0].tracks.first { $0.id == videoTrack.id }?.clips.count == videoTrack.clips.count + 1)

        undoManager.beginUndoGrouping()
        editor.deleteClips([firstClipID], ripple: true)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "리플 삭제")
        #expect(editor.project.sequences[0].clip(id: firstClipID) == nil)

        undoManager.undo()
        undoManager.undo()
        #expect(editor.project.sequences[0].tracks.first { $0.id == videoTrack.id } == videoTrack)
    }

    @Test("새 시퀀스를 만들면 현재 시퀀스가 되고, 클립 편집은 현재 시퀀스에만 적용되며, 지우면 첫 시퀀스로 돌아간다")
    func sequenceCommands() throws {
        let editor = try makeEditorWithSampleContent()
        let firstSequence = editor.currentSequence

        let newID = editor.addSequence(named: "하이라이트")
        #expect(editor.currentSequenceID == newID)
        editor.placeAsset(SampleData.introVideo.id, onTrack: nil, at: .zero)
        #expect(editor.currentSequence.tracks.flatMap(\.clips).count == 1)
        #expect(editor.project.sequences[0] == firstSequence)

        editor.renameSequence(newID, to: "쇼츠")
        #expect(editor.currentSequence.name == "쇼츠")

        editor.switchToSequence(firstSequence.id)
        #expect(editor.currentSequence == firstSequence)

        editor.switchToSequence(newID)
        editor.deleteSequence(newID)
        #expect(editor.currentSequenceID == firstSequence.id)
        #expect(editor.project.sequences.count == 1)
    }

    // MARK: - Helpers

    /// 샘플 내용을 저장한 프로젝트를 여는 편집기.
    private func makeEditorWithSampleContent() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }

    private func makeSilentAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }
}
