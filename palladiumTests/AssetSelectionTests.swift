import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 미디어 패널 다중 선택(#86): 고른 순서, 끌기 내용, 차례로 이어 놓기.
struct AssetSelectionOrderTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    @Test("⌘ 클릭으로 하나씩 더하면 고른 순서가 되고, 빠진 원본은 순서에서도 빠진다")
    func clickOrder() {
        let list = [a, b, c, d]
        var order = AssetSelectionOrder.updated([], selection: [c], listOrder: list)
        order = AssetSelectionOrder.updated(order, selection: [c, a], listOrder: list)
        order = AssetSelectionOrder.updated(order, selection: [c, a, d], listOrder: list)
        #expect(order == [c, a, d])
        order = AssetSelectionOrder.updated(order, selection: [c, d], listOrder: list)
        #expect(order == [c, d])
    }

    @Test("⇧ 클릭·⌘A처럼 한꺼번에 더해진 범위는 목록에 보이는 순서로 뒤에 붙는다")
    func rangeUsesListOrder() {
        let list = [a, b, c, d]
        let order = AssetSelectionOrder.updated([c], selection: [a, b, c, d], listOrder: list)
        #expect(order == [c, a, b, d])
        #expect(AssetSelectionOrder.ordered([d, b], by: [d], listOrder: list) == [d, b])
    }

    @Test("끄는 원본 여러 개를 순서대로 담았다 풀고, 예전 형식(ID 하나)과 섞인 글자도 읽는다")
    func dragPayload() {
        let text = AssetDragPayload.encode([c, a, b])
        #expect(AssetDragPayload.decode(text) == [c, a, b])
        #expect(AssetDragPayload.decode(a.uuidString) == [a])
        #expect(AssetDragPayload.decode("file:///tmp/x.mov") == [])
    }
}

/// 여러 원본을 타임라인에 차례로 이어 놓기(#86).
@MainActor
struct PlaceAssetsTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.autosaveEnabled = false
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("영상·오디오가 섞이면 각자 자기 종류 트랙에 같은 시각부터 고른 순서대로 이어 놓고, 뒤 클립은 밀리며, 실행 취소 한 번에 사라진다")
    func placesMixedKindsInOrder() throws {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        let editor = ProjectEditor(project: project, repository: repository)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let videoTrack = try #require(editor.currentSequence.tracks.first { $0.kind == .video })
        let before = editor.project
        let laterClip = try #require(videoTrack.clips.max { $0.timelineStart < $1.timelineStart })

        // 맨 앞(0초)에 B컷 → 배경음악 → 인트로 순서로 놓는다.
        undoManager.beginUndoGrouping()
        let placed = editor.placeAssets(
            [SampleData.bRollVideo.id, SampleData.backgroundMusic.id, SampleData.introVideo.id],
            preferredTracks: [.video: videoTrack.id],
            at: .zero
        )
        undoManager.endUndoGrouping()

        #expect(placed.count == 3)
        let clips = placed.compactMap { editor.currentSequence.clip(id: $0) }
        let bRoll = clips[0]
        let music = clips[1]
        let intro = clips[2]
        #expect(bRoll.timelineStart == .zero)
        #expect(intro.timelineStart == bRoll.timelineRange.end)
        #expect(music.timelineStart == .zero)
        #expect(editor.currentSequence.trackID(containing: bRoll.id) == videoTrack.id)
        #expect(editor.currentSequence.trackID(containing: intro.id) == videoTrack.id)
        #expect(editor.currentSequence.tracks.first { $0.id == editor.currentSequence.trackID(containing: music.id) }?.kind == .audio)
        // 원래 있던 클립은 놓은 두 영상 길이만큼 뒤로 밀렸다.
        let pushed = try #require(editor.currentSequence.clip(id: laterClip.id))
        #expect(pushed.timelineStart == laterClip.timelineStart + bRoll.timelineDuration + intro.timelineDuration)
        #expect(editor.currentSequence.tracks.count == before.sequences[0].tracks.count)
        #expect(undoManager.undoActionName == "클립 배치")

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("그 종류 트랙이 하나도 없을 때만 새 트랙을 만든다")
    func createsTrackOnlyWhenMissing() throws {
        let editor = try ProjectEditor(project: repository.createProject(named: "빈 프로젝트"), repository: repository)
        editor.applyDebugChange { $0.assets = [SampleData.introVideo, SampleData.bRollVideo] }

        let placed = editor.placeAssets([SampleData.introVideo.id, SampleData.bRollVideo.id], at: .zero)

        let tracks = editor.currentSequence.tracks
        #expect(tracks.map(\.kind) == [.video])
        #expect(tracks[0].clips.map(\.id) == placed)
        #expect(tracks[0].clips[1].timelineStart == tracks[0].clips[0].timelineRange.end)
    }
}
