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
        // 저장소는 직접 저장한다. 자동 저장 타이머가 테스트가 끝나 사라진 컨테이너에 불리면 앱이 멈추므로 끈다.
        container.mainContext.autosaveEnabled = false
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

    @Test("녹음한 내레이션은 가져와서 녹음을 시작한 시각에 놓고, 그 구간이 빈 오디오 트랙이 없으면 새 트랙을 만들어 기존 클립을 밀지 않는다")
    func narrationIsImportedAndPlaced() async throws {
        let editor = try makeEditorWithSampleContent()
        let musicClip = try #require(editor.currentSequence.tracks.first { $0.kind == .audio }?.clips.first)
        let atFive = CMTime(seconds: 5, preferredTimescale: standardTimescale)
        let atThirty = CMTime(seconds: 30, preferredTimescale: standardTimescale)

        // 배경음악(0~18초)이 있는 구간: 새 오디오 트랙에 놓는다.
        let firstID = try #require(await editor.addNarration(from: makeSilentAudio(), at: atFive))
        // 배경음악이 끝난 뒤: 기존 오디오 트랙의 빈 곳에 놓는다.
        let secondID = try #require(await editor.addNarration(from: makeSilentAudio(), at: atThirty))

        let audioTracks = editor.currentSequence.tracks.filter { $0.kind == .audio }
        #expect(audioTracks.count == 2)
        #expect(audioTracks[0].clips.map(\.id).contains(secondID))
        #expect(audioTracks[1].clips.map(\.id) == [firstID])
        #expect(editor.currentSequence.clip(id: firstID)?.timelineStart == atFive)
        #expect(editor.currentSequence.clip(id: secondID)?.timelineStart == atThirty)
        #expect(editor.currentSequence.clip(id: musicClip.id) == musicClip)
        #expect(editor.project.assets.count == SampleData.project.assets.count + 2)
    }

    @Test("트림과 시간 입력은 원본 범위 안으로 맞춘다")
    func trimCommands() throws {
        let editor = try makeEditorWithSampleContent()
        let clip = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips.first)
        let assetDuration = try #require(editor.asset(id: clip.assetID)?.duration)

        editor.trimClip(clip.id, edge: .end, by: CMTime(value: 1000, timescale: 1))
        #expect(editor.currentSequence.clip(id: clip.id)?.sourceRange.end == assetDuration)

        editor.setClipSource(clip.id, start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1))
        #expect(editor.currentSequence.clip(id: clip.id)?.sourceRange == CMTimeRange(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 2, timescale: 1)))
    }

    @Test("트랜스폼은 배율·불투명도를 범위로 맞춰 저장하고, 분할한 조각도 같은 트랜스폼을 가진다")
    func transformCommands() throws {
        let editor = try makeEditorWithSampleContent()
        let clip = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips.first)

        editor.setTransform(ClipTransform(centerX: 0.8, centerY: 0.2, scale: 99, opacity: 2), for: clip.id)
        let stored = try #require(editor.currentSequence.clip(id: clip.id)?.transform)
        #expect(stored == ClipTransform(centerX: 0.8, centerY: 0.2, scale: ClipTransform.scaleRange.upperBound, opacity: 1))

        editor.splitClips([clip.id], at: clip.timelineStart + CMTime(value: 1, timescale: 1))
        let pieces = editor.currentSequence.tracks.flatMap(\.clips).filter { $0.assetID == clip.assetID }
        #expect(pieces.count >= 2)
        #expect(pieces.allSatisfy { $0.transform == stored })

        try editor.save()
        #expect(try repository.project(id: editor.project.id) == editor.project)
    }

    @Test("클립·트랙 음량과 음소거를 바꾸고 저장하면 그대로 불러온다")
    func audioCommands() throws {
        let editor = try makeEditorWithSampleContent()
        let audioTrack = try #require(editor.currentSequence.tracks.first { $0.kind == .audio })
        let clipID = try #require(audioTrack.clips.first?.id)

        editor.setClipAudio(volume: 3, isMuted: false, for: clipID)
        editor.setTrackAudio(volume: 0.5, isMuted: true, for: audioTrack.id)

        #expect(editor.currentSequence.clip(id: clipID)?.volume == 1)
        #expect(editor.currentSequence.tracks.first { $0.id == audioTrack.id }?.isMuted == true)
        try editor.save()
        #expect(try repository.project(id: editor.project.id) == editor.project)
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

    @Test("원본을 지우면 폴더와 모든 시퀀스의 그 원본 클립도 지우고, 다른 클립은 제자리에 두며, 실행 취소 한 번으로 모두 돌아온다")
    func deleteAssetsRemovesClipsEverywhere() throws {
        let editor = try makeEditorWithSampleContent()
        let introID = SampleData.introVideo.id
        // 두 번째 시퀀스에도 같은 원본을 놓는다.
        editor.addSequence(named: "하이라이트")
        editor.placeAsset(introID, onTrack: nil, at: .zero)
        editor.switchToSequence(editor.project.sequences[0].id)
        // 실행 취소 관리자는 준비가 끝난 뒤 붙인다(묶음 밖에서 실행 취소를 남기면 예외가 나 테스트가 멈춘다).
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let bRollClip = try #require(editor.currentSequence.tracks.flatMap(\.clips).first { $0.assetID == SampleData.bRollVideo.id })
        let before = editor.project

        let usage = editor.clipUsage(of: [introID])
        #expect(usage.clipCount == 2)
        #expect(usage.sequenceNames == ["통합본", "하이라이트"])
        #expect(editor.clipUsage(of: [SampleData.backgroundMusic.id]).sequenceNames == ["통합본"])

        undoManager.beginUndoGrouping()
        editor.deleteAssets([introID])
        undoManager.endUndoGrouping()

        #expect(editor.asset(id: introID) == nil)
        #expect(editor.project.folders.allSatisfy { !$0.assetIDs.contains(introID) })
        #expect(editor.project.sequences.allSatisfy { sequence in !sequence.tracks.flatMap(\.clips).contains { $0.assetID == introID } })
        // 지운 자리는 빈 틈으로 남고 뒤 클립은 움직이지 않는다.
        #expect(editor.currentSequence.clip(id: bRollClip.id) == bRollClip)
        #expect(editor.clipUsage(of: [introID]).clipCount == 0)
        #expect(undoManager.undoActionName == "원본 삭제")

        undoManager.undo()
        #expect(editor.project == before)
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

    @Test("클립 별칭은 앞뒤 공백을 빼고 저장하며, 비우면 다시 원본 이름을 보여주고, 원본 이름을 바꿔도 별칭은 그대로다")
    func renameClip() throws {
        let editor = try makeEditorWithSampleContent()
        let clips = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips)
        let named = clips[0]
        let unnamedID = try #require(clips.first { $0.assetID != named.assetID }?.id)
        let unnamedAssetID = try #require(editor.currentSequence.clip(id: unnamedID)?.assetID)
        let assetName = try #require(editor.asset(id: named.assetID)?.name)
        // 기본은 별칭이 없어 원본 이름을 보여준다.
        #expect(named.name == nil)
        #expect(named.displayName(assetName: assetName) == assetName)

        editor.renameClip(named.id, to: "  인트로 \n")
        #expect(editor.currentSequence.clip(id: named.id)?.name == "인트로")

        editor.renameAsset(named.assetID, to: "오프닝 원본")
        editor.renameAsset(unnamedAssetID, to: "새 원본 이름")
        #expect(editor.currentSequence.clip(id: named.id)?.displayName(assetName: "오프닝 원본") == "인트로")
        let unnamed = try #require(editor.currentSequence.clip(id: unnamedID))
        #expect(try unnamed.displayName(assetName: #require(editor.asset(id: unnamedAssetID)?.name)) == "새 원본 이름")

        editor.renameClip(named.id, to: "   ")
        #expect(editor.currentSequence.clip(id: named.id)?.name == nil)
        #expect(editor.currentSequence.clip(id: named.id)?.displayName(assetName: "오프닝 원본") == "오프닝 원본")
    }

    @Test("클립 색상 레이블은 고른 클립 모두에 붙고 \"없음\"으로 떼며, 나눈 조각도 같은 별칭·색을 가진다")
    func setClipColorLabel() throws {
        let editor = try makeEditorWithSampleContent()
        let clips = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips)
        let ids: Set<Clip.ID> = [clips[0].id, clips[1].id]

        editor.setClipColorLabel(.green, for: ids)
        let labeledIDs = Set(editor.currentSequence.tracks.flatMap(\.clips).filter { $0.colorLabel == ColorLabel.green }.map(\.id))
        #expect(labeledIDs == ids)

        editor.setClipColorLabel(nil, for: [clips[1].id])
        #expect(editor.currentSequence.clip(id: clips[1].id)?.colorLabel == nil)
        #expect(editor.currentSequence.clip(id: clips[0].id)?.colorLabel == .green)

        editor.renameClip(clips[0].id, to: "후렴")
        editor.splitClips([clips[0].id], at: clips[0].timelineStart + CMTime(value: 1, timescale: 1))
        let pieces = editor.currentSequence.tracks.flatMap(\.clips).filter { $0.assetID == clips[0].assetID }
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.name == "후렴" && $0.colorLabel == .green })
        #expect(editor.hasUnsavedChanges)
    }

    @Test("클립 이름·색 변경은 실행 취소 한 번으로 되돌린다")
    func clipLabelEditsUndo() throws {
        let editor = try makeEditorWithSampleContent()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let clips = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips)
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.renameClip(clips[0].id, to: "인트로")
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "클립 이름 변경")
        undoManager.undo()
        #expect(editor.project == before)

        undoManager.beginUndoGrouping()
        editor.setClipColorLabel(.red, for: [clips[0].id, clips[1].id])
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "클립 색상 레이블")
        undoManager.undo()
        #expect(editor.project == before)
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
