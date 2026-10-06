import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 클립·자막·마스크 복사·잘라내기·붙여넣기·복제(#62). 샘플 시퀀스: 영상(인트로 0~8초, B컷 8~18초), 오디오(배경음악 0~18초).
@MainActor
struct ClipboardTests {
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

    @Test("붙여넣은 클립은 트림·트랜스폼·음량·속도·전환·별칭·색을 그대로 갖고 새 ID를 받는다")
    func pastedClipKeepsAttributes() throws {
        let editor = try makeEditor()
        let bRoll = try #require(videoClips(editor).last)
        editor.setTransform(ClipTransform(centerX: 0.3, centerY: 0.6, scale: 0.5, opacity: 0.8), for: bRoll.id)
        editor.setClipAudio(volume: 0.4, isMuted: true, for: bRoll.id)
        editor.setClipSpeed(2, for: bRoll.id)
        editor.renameClip(bRoll.id, to: "바닷가")
        editor.setClipColorLabel(.blue, for: [bRoll.id])
        let original = try #require(editor.currentSequence.clip(id: bRoll.id))

        editor.copyClips([bRoll.id])
        let pasted = try #require(editor.pasteClips(at: original.timelineRange.end))

        guard case let .clips(pastedIDs) = pasted else { Issue.record("클립이 붙지 않음"); return }
        #expect(pastedIDs.count == 1)
        let copy = try #require(pastedIDs.first.flatMap { editor.currentSequence.clip(id: $0) })
        #expect(copy.id != original.id)
        #expect(copy.timelineStart == original.timelineRange.end)
        var expected = original
        expected.timelineStart = copy.timelineStart
        #expect(Clip.sameContent(copy, expected))
        #expect(copy.transitionIn == original.transitionIn)
    }

    @Test("클립 중간에 붙이면 가까운 경계에 들어가고 뒤 클립을 민다")
    func pasteSnapsToBoundaryAndPushes() throws {
        let editor = try makeEditor()
        let clips = videoClips(editor)
        editor.copyClips([clips[0].id])

        // 인트로(0~8초)의 앞쪽 절반이라 인트로 앞 경계(0초)에 들어간다.
        _ = editor.pasteClips(at: seconds(3))

        let after = videoClips(editor)
        #expect(after.count == 3)
        #expect(after.map(\.timelineStart) == [seconds(0), seconds(8), seconds(16)])
        #expect(after[1].id == clips[0].id)
        #expect(after[2].id == clips[1].id)
    }

    @Test("여러 트랙을 붙이면 기준 트랙(가장 먼저 시작하는 클립의 트랙) 경계에 맞추고 트랙 사이 상대 위치를 지킨다")
    func multiTrackPasteKeepsRelativePositions() throws {
        let editor = try makeEditor()
        let intro = videoClips(editor)[0]
        let music = try #require(audioClips(editor).first)
        editor.copyClips([intro.id, music.id])

        // 두 트랙 모두 18초가 끝이라 그대로 18초에 들어간다.
        let pasted = try #require(editor.pasteClips(at: seconds(18)))

        guard case let .clips(ids) = pasted else { Issue.record("클립이 붙지 않음"); return }
        #expect(ids.count == 2)
        let pastedClips = ids.compactMap { editor.currentSequence.clip(id: $0) }
        #expect(pastedClips.allSatisfy { $0.timelineStart == seconds(18) })
        #expect(Set(pastedClips.map(\.assetID)) == [intro.assetID, music.assetID])
    }

    @Test("기준 트랙 시각이 다른 트랙에서 클립 중간이면 그 트랙에서는 걸친 클립 뒤 경계에 넣는다(클립을 나누지 않는다)")
    func multiTrackPasteMovesPastStraddlingClip() throws {
        let editor = try makeEditor()
        let intro = videoClips(editor)[0]
        let music = try #require(audioClips(editor).first)
        editor.copyClips([intro.id, music.id])

        // 영상 트랙 기준: 8초는 경계라 그대로. 오디오 트랙은 배경음악(0~18초)에 걸리므로 18초로 간다.
        _ = editor.pasteClips(at: seconds(8))

        let video = videoClips(editor)
        #expect(video.map(\.timelineStart) == [seconds(0), seconds(8), seconds(16)])
        #expect(video[1].assetID == intro.assetID)
        let audio = audioClips(editor)
        #expect(audio.map(\.timelineStart) == [seconds(0), seconds(18)])
        #expect(audio.count == 2)
    }

    @Test("다른 시퀀스에 붙이면 같은 번호의 같은 종류 트랙에 넣고, 모자라면 가장 가까운 트랙에, 그 종류 트랙이 없으면 붙이지 않는다")
    func pasteIntoOtherSequence() throws {
        let editor = try makeEditor()
        let intro = videoClips(editor)[0]
        let music = try #require(audioClips(editor).first)
        editor.copyClips([intro.id, music.id])

        editor.addSequence(named: "하이라이트")
        // 트랙이 하나도 없으면 아무것도 붙이지 않고 새 트랙도 만들지 않는다.
        #expect(editor.pasteClips(at: .zero) == nil)
        #expect(editor.currentSequence.tracks.isEmpty)

        let firstVideo = editor.addTrack(kind: .video)
        let overlay = editor.addTrack(kind: .video)
        let pasted = try #require(editor.pasteClips(at: .zero))

        guard case let .clips(ids) = pasted else { Issue.record("클립이 붙지 않음"); return }
        #expect(ids.count == 1)
        // 영상 1(맨 아래, 메인)에서 복사했으므로 영상 1에 들어간다. 오디오 트랙이 없어 배경음악은 붙지 않는다.
        #expect(editor.currentSequence.tracks.first { $0.id == firstVideo }?.clips.map(\.assetID) == [intro.assetID])
        #expect(editor.currentSequence.tracks.first { $0.id == overlay }?.clips.isEmpty == true)
        #expect(editor.currentSequence.tracks.allSatisfy { $0.kind == .video })
    }

    @Test("지운 원본의 클립은 붙여넣지 않는다")
    func pasteSkipsDeletedAssets() throws {
        let editor = try makeEditor()
        let clips = videoClips(editor)
        editor.copyClips([clips[0].id])
        editor.deleteAssets([clips[0].assetID])
        let before = editor.project

        #expect(editor.pasteClips(at: .zero) == nil)
        #expect(editor.project == before)
    }

    @Test("잘라내기는 지운 자리를 메우고, 붙여넣기·잘라내기·복제는 각각 실행 취소 한 번으로 되돌린다")
    func cutPasteDuplicateUndo() throws {
        let editor = try makeEditor()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let clips = videoClips(editor)
        let start = editor.project

        undoManager.beginUndoGrouping()
        editor.cutClips([clips[0].id])
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "잘라내기")
        #expect(editor.currentSequence.clip(id: clips[0].id) == nil)
        #expect(videoClips(editor).first?.timelineStart == .zero)
        let afterCut = editor.project

        undoManager.beginUndoGrouping()
        _ = editor.pasteClips(at: seconds(10))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "붙여넣기")
        #expect(videoClips(editor).count == 2)
        undoManager.undo()
        #expect(editor.project == afterCut)
        undoManager.undo()
        #expect(editor.project == start)

        undoManager.beginUndoGrouping()
        let duplicated = editor.duplicateClips([clips[0].id])
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "복제")
        #expect(duplicated.count == 1)
        undoManager.undo()
        #expect(editor.project == start)
    }

    @Test("복제는 고른 클립 바로 뒤에 넣고 뒤 클립을 밀며, 클립보드는 바꾸지 않는다")
    func duplicatePlacesRightAfterSelection() throws {
        let editor = try makeEditor()
        let clips = videoClips(editor)

        let duplicated = editor.duplicateClips([clips[0].id])

        let after = videoClips(editor)
        #expect(after.map(\.timelineStart) == [seconds(0), seconds(8), seconds(16)])
        #expect(duplicated == [after[1].id])
        #expect(after[1].assetID == clips[0].assetID)
        #expect(editor.clipboard == nil)
    }

    @Test("자막·마스크는 재생 헤드에 같은 길이·모양으로 붙고 다른 블록을 밀지 않는다")
    func pasteSubtitleAndMask() throws {
        let editor = try makeEditor()
        let subtitles = editor.currentSequence.subtitles
        let mask = try #require(editor.currentSequence.masks.first)

        editor.copySubtitle(subtitles[1].id)
        let pastedSubtitle = try #require(editor.pasteClips(at: seconds(2)))
        guard case let .subtitle(subtitleID) = pastedSubtitle else { Issue.record("자막이 붙지 않음"); return }
        let copy = try #require(editor.currentSequence.subtitles.first { $0.id == subtitleID })
        #expect(copy.id != subtitles[1].id)
        #expect(copy.range == CMTimeRange(start: seconds(2), duration: subtitles[1].range.duration))
        #expect(copy.text == subtitles[1].text)
        #expect(copy.style == subtitles[1].style)
        // 겹친 자막(1~4초)도 그대로 둔다.
        #expect(editor.currentSequence.subtitles.filter { $0.id != subtitleID } == subtitles)

        editor.copyMask(mask.id)
        let pastedMask = try #require(editor.pasteClips(at: seconds(10)))
        guard case let .mask(maskID) = pastedMask else { Issue.record("마스크가 붙지 않음"); return }
        let maskCopy = try #require(editor.currentSequence.masks.first { $0.id == maskID })
        #expect(maskCopy.range == CMTimeRange(start: seconds(10), duration: mask.range.duration))
        #expect(maskCopy.area == mask.area && maskCopy.shape == mask.shape && maskCopy.effect == mask.effect && maskCopy.strength == mask.strength)
        #expect(editor.currentSequence.masks.first { $0.id == mask.id } == mask)
    }

    // MARK: - Helpers

    private func makeEditor() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }

    private func videoClips(_ editor: ProjectEditor) -> [Clip] {
        editor.currentSequence.tracks.first { $0.kind == .video }?.clips ?? []
    }

    private func audioClips(_ editor: ProjectEditor) -> [Clip] {
        editor.currentSequence.tracks.first { $0.kind == .audio }?.clips ?? []
    }

    private func seconds(_ value: Int64) -> CMTime {
        CMTime(value: value * Int64(standardTimescale), timescale: standardTimescale)
    }
}

private extension Clip {
    /// ID만 빼고 같은지.
    static func sameContent(_ lhs: Clip, _ rhs: Clip) -> Bool {
        lhs.assetID == rhs.assetID && lhs.sourceRange == rhs.sourceRange && lhs.timelineStart == rhs.timelineStart
            && lhs.transform == rhs.transform && lhs.volume == rhs.volume && lhs.isMuted == rhs.isMuted
            && lhs.transitionIn == rhs.transitionIn && lhs.audioCrossfadeIn == rhs.audioCrossfadeIn
            && lhs.speed == rhs.speed && lhs.name == rhs.name && lhs.colorLabel == rhs.colorLabel
    }
}
