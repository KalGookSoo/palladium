import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 타임라인 병합(#100): 맞닿은 클립을 그룹으로 묶어 한 번에 고르고 옮기고 지우기. 컴파운드 클립이 아니라 묶음이다.
@MainActor
struct ClipGroupTests {
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

    /// 영상 트랙: A 0~2, B 2~4, C 4~6, (틈) D 8~10. 오디오 트랙: E 0~3.
    private func makeSequence() throws -> (EditSequence, [Clip.ID]) {
        let asset = UUID()
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let video = sequence.addTrack(kind: .video)
        let audio = sequence.addTrack(kind: .audio)
        var ids: [Clip.ID] = []
        for (start, end) in [(0.0, 2.0), (2, 4), (4, 6), (8, 10)] {
            let clip = try #require(Clip(assetID: asset, sourceRange: range(start, end), timelineStart: seconds(start)))
            sequence.tracks[sequence.tracks.firstIndex { $0.id == video }!].clips.append(clip)
            ids.append(clip.id)
        }
        let sound = try #require(Clip(assetID: asset, sourceRange: range(0, 3), timelineStart: .zero))
        sequence.tracks[sequence.tracks.firstIndex { $0.id == audio }!].clips.append(sound)
        ids.append(sound.id)
        return (sequence, ids)
    }

    @Test("같은 트랙에서 맞닿은 2개 이상만 묶을 수 있고, 틈·다른 트랙·이미 한 그룹이면 묶을 수 없다")
    func canGroup() throws {
        var (sequence, ids) = try makeSequence()
        #expect(sequence.canGroup([ids[0], ids[1]]))
        #expect(sequence.canGroup([ids[0], ids[1], ids[2]]))
        #expect(!sequence.canGroup([ids[0]]))
        #expect(!sequence.canGroup([ids[0], ids[2]]))
        #expect(!sequence.canGroup([ids[2], ids[3]]))
        #expect(!sequence.canGroup([ids[0], ids[4]]))

        let firstGroup = sequence.group([ids[0], ids[1]])
        let groupID = try #require(firstGroup)
        #expect(!sequence.canGroup([ids[0]]))
        #expect(!sequence.canGroup([ids[0], ids[1]]))
        // 그룹에 맞닿은 클립을 더하면 하나의 새 그룹으로 합쳐진다.
        #expect(sequence.canGroup([ids[1], ids[2]]))
        let mergedGroup = sequence.group([ids[1], ids[2]])
        let merged = try #require(mergedGroup)
        #expect(merged != groupID)
        #expect([ids[0], ids[1], ids[2]].allSatisfy { sequence.clip(id: $0)?.groupID == merged })
        #expect(sequence.expandedToGroups([ids[2]]) == [ids[0], ids[1], ids[2]])

        sequence.ungroup([ids[1]])
        #expect([ids[0], ids[1], ids[2]].allSatisfy { sequence.clip(id: $0)?.groupID == nil })
        #expect(!sequence.canUngroup([ids[0]]))
    }

    @Test("그룹 안 시각에 놓으면 그룹 사이에 끼우지 않고 그룹 앞이나 뒤로 놓는다")
    func insertionAvoidsGroups() throws {
        var (sequence, ids) = try makeSequence()
        sequence.group([ids[0], ids[1], ids[2]])
        let track = sequence.tracks[0]
        #expect(track.insertionPoint(for: seconds(2.5)) == .zero)
        #expect(track.insertionPoint(for: seconds(3.5)) == seconds(6))
        let newClip = try #require(Clip(assetID: UUID(), sourceRange: range(0, 1), timelineStart: seconds(3.5)))
        sequence.place(newClip, onTrack: track.id)
        #expect(sequence.clip(id: newClip.id)?.timelineStart == seconds(6))
        #expect(sequence.clip(id: ids[2])?.timelineRange.end == seconds(6))
    }

    @Test("그룹 클립을 끌면 그룹 전체가 맞닿은 채 옮겨지고, 다른 트랙으로도 옮겨진다")
    func moveGroup() throws {
        var (sequence, ids) = try makeSequence()
        sequence.group([ids[0], ids[1]])
        // B를 끌어 D 뒤(10초)로: 그룹 A·B가 통째로 C·D 뒤로 간다.
        sequence.moveClip(ids[1], toTrack: sequence.tracks[0].id, at: seconds(12))
        let a = try #require(sequence.clip(id: ids[0]))
        let b = try #require(sequence.clip(id: ids[1]))
        #expect(b.timelineStart == a.timelineRange.end)
        #expect(sequence.clip(id: ids[2])?.timelineStart == .zero)
        #expect(a.timelineStart == sequence.clip(id: ids[3])?.timelineRange.end)

        // 새 영상 트랙으로.
        let overlay = sequence.addTrack(kind: .video)
        sequence.moveClip(ids[0], toTrack: overlay, at: seconds(1))
        #expect(sequence.trackID(containing: ids[0]) == overlay && sequence.trackID(containing: ids[1]) == overlay)
        #expect(sequence.clip(id: ids[0])?.timelineStart == seconds(1))
        #expect(sequence.clip(id: ids[1])?.timelineStart == seconds(3))
    }

    @Test("그룹 안 클립 하나를 트림해도 안은 붙은 채이고, 나눈 조각은 그룹에 남는다")
    func trimAndSplitInsideGroup() throws {
        var (sequence, ids) = try makeSequence()
        let newGroup = sequence.group([ids[0], ids[1], ids[2]])
        let groupID = try #require(newGroup)
        sequence.setSourceRange(range(0, 1), forClip: ids[0])
        #expect(sequence.clip(id: ids[1])?.timelineStart == seconds(1))
        #expect(sequence.clip(id: ids[2])?.timelineStart == seconds(3))
        sequence.split(at: seconds(2), clipIDs: [ids[1]])
        #expect(sequence.tracks[0].members(ofGroup: groupID).count == 4)
    }

    @Test("편집기: 병합·병합 해제는 실행 취소 한 번씩, 지우기·복사는 그룹 통째로, 붙인 그룹은 새 그룹이다. 저장 후에도 남는다")
    func editor() throws {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        let editor = ProjectEditor(project: project, repository: repository)
        let clips = try #require(editor.currentSequence.tracks.first?.clips)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        _ = editor.groupClips(Set(clips.map(\.id)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "병합")
        undoManager.undo()
        #expect(editor.project == before)

        // 묶음 없이 편집을 남기면 예외가 나 스위트가 끝나지 않으므로, 나머지는 실행 취소 관리자 없이 확인한다.
        editor.undoManager = nil
        let groupID = try #require(editor.groupClips(Set(clips.map(\.id))))
        editor.ungroupClips([clips[0].id])
        #expect(editor.currentSequence.clip(id: clips[0].id)?.groupID == nil)
        #expect(editor.groupClips(Set(clips.map(\.id))) != nil)
        let currentGroup = try #require(editor.currentSequence.clip(id: clips[0].id)?.groupID)

        editor.copyClips([clips[0].id])
        guard case let .clips(pastedIDs)? = editor.pasteClips(at: seconds(30)) else {
            Issue.record("붙여넣지 못했다")
            return
        }
        let pastedGroups = Set(pastedIDs.compactMap { editor.currentSequence.clip(id: $0)?.groupID })
        #expect(pastedIDs.count == 2 && pastedGroups.count == 1 && pastedGroups.first != currentGroup && groupID != currentGroup)

        try editor.save()
        #expect(try repository.project(id: project.id) == editor.project)

        editor.deleteClips([clips[0].id], ripple: false)
        #expect(editor.currentSequence.clip(id: clips[1].id) == nil)
    }

    private func range(_ start: Double, _ end: Double) -> CMTimeRange {
        CMTimeRange(start: seconds(start), end: seconds(end))
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
