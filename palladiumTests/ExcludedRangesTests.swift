import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 구간 빼기(#99): 클립 편집 창에서 여러 구간을 빼고 남은 구간들을 이어 붙인 파생 항목 저장·배치, 타임라인 클립에 적용(나누기 + 리플).
/// 샘플: 인트로 원본(10초, "촬영본" 폴더 첫 항목), 영상 트랙 인트로 클립 0~8초(원본 0~8초)·B컷 8~18초.
@MainActor
struct ExcludedRangesTests {
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

    // MARK: - 규칙

    @Test("뺀 구간은 바깥 구간 안으로 자르고, 겹치거나 맞닿으면 하나로 합친다")
    func normalize() {
        let bounds = range(0, 10)
        let normalized = RangeExclusion.normalized([range(6, 8), range(1, 3), range(2, 4), range(8, 9), range(9.5, 12)], within: bounds)
        #expect(normalized == [range(1, 4), range(6, 9), range(9.5, 10)])
        #expect(RangeExclusion.normalized([range(11, 12)], within: bounds).isEmpty)
    }

    @Test("남은 구간은 뺀 구간 사이의 조각이고, 한 프레임보다 짧은 조각은 버린다. 길이는 남은 구간의 합이다")
    func keptRanges() {
        let bounds = range(0, 10)
        #expect(RangeExclusion.kept(bounds: bounds, excluded: []) == [bounds])
        #expect(RangeExclusion.kept(bounds: bounds, excluded: [range(2, 3), range(5, 7)]) == [range(0, 2), range(3, 5), range(7, 10)])
        #expect(RangeExclusion.keptDuration(bounds: bounds, excluded: [range(2, 3), range(5, 7)]) == seconds(7))
        // 앞에 1/60초만 남으면 버린다.
        let almostAll = CMTimeRange(start: CMTime(value: 10, timescale: 600), end: seconds(5))
        #expect(RangeExclusion.kept(bounds: bounds, excluded: [almostAll]) == [range(5, 10)])
        // 전부 빼면 남는 것이 없다.
        #expect(RangeExclusion.kept(bounds: bounds, excluded: [bounds]).isEmpty)
    }

    @Test("남은 구간을 감싸는 구간과 그 안의 빈 곳으로 정리한다(양 끝을 뺐으면 감싸는 구간이 줄어든다)")
    func hullAndGaps() throws {
        let kept = RangeExclusion.kept(bounds: range(0, 10), excluded: [range(0, 1), range(4, 5), range(9, 10)])
        let (hull, gaps) = try #require(RangeExclusion.hullAndGaps(of: kept))
        #expect(hull == range(1, 9))
        #expect(gaps == [range(4, 5)])
        #expect(RangeExclusion.hullAndGaps(of: []) == nil)
        #expect(RangeExclusion.excludedRange(containing: seconds(4.5), in: gaps) == range(4, 5))
        #expect(RangeExclusion.excludedRange(containing: seconds(5), in: gaps) == nil)
    }

    // MARK: - 파생 항목

    @Test("구간을 빼고 새 항목으로 저장하면 길이가 남은 구간의 합인 파생 항목 하나가 생기고, 실행 취소 한 번으로 돌아온다")
    func saveDerivedWithExclusions() throws {
        let editor = try makeEditor()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let newID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: .zero, end: seconds(10), excluded: [range(2, 3), range(5, 7)]))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "새 항목으로 저장")

        let derived = try #require(editor.asset(id: newID))
        #expect(derived.isDerived && derived.mediaKey == SampleData.introVideo.mediaKey)
        #expect(derived.usedRange == nil)
        #expect(derived.excludedRanges == [range(2, 3), range(5, 7)])
        #expect(derived.keptRanges == [range(0, 2), range(3, 5), range(7, 10)])
        #expect(derived.placementDuration == seconds(7))
        #expect(editor.asset(id: SampleData.introVideo.id) == SampleData.introVideo)

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("양 끝을 빼면 쓰는 구간이 줄어들고, 이름은 남은 구간을 감싸는 구간으로 짓는다. 전부 빼면 저장되지 않는다")
    func edgeExclusionShrinksRange() throws {
        let editor = try makeEditor()
        let newID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(1), end: seconds(9), excluded: [range(1, 2), range(4, 5)]))
        let derived = try #require(editor.asset(id: newID))
        #expect(derived.usedRange == range(2, 9))
        #expect(derived.excludedRanges == [range(4, 5)])
        #expect(derived.name == "intro (0:02.0–0:09.0).mov")

        let count = editor.project.assets.count
        #expect(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(1), end: seconds(9), excluded: [range(0, 10)]) == nil)
        #expect(editor.project.assets.count == count)
    }

    @Test("파생 항목에 적용하면 뺀 구간을 바꾸고, 되살려 적용하면 뺀 구간이 없어진다. 전부 빼고 적용하면 바뀌지 않는다")
    func applyToDerived() throws {
        let editor = try makeEditor()
        let newID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(2), end: seconds(8)))
        editor.setUsedRange(start: seconds(2), end: seconds(8), excluded: [range(3, 4)], for: newID)
        #expect(editor.asset(id: newID)?.excludedRanges == [range(3, 4)])
        #expect(editor.asset(id: newID)?.placementDuration == seconds(5))

        let applied = editor.asset(id: newID)
        editor.setUsedRange(start: seconds(2), end: seconds(8), excluded: [range(2, 8)], for: newID)
        #expect(editor.asset(id: newID) == applied)

        editor.setUsedRange(start: seconds(2), end: seconds(8), for: newID)
        #expect(editor.asset(id: newID)?.excludedRanges == [])
        #expect(editor.asset(id: newID)?.usedRange == range(2, 8))
    }

    @Test("뺀 구간이 있는 항목을 놓으면 남은 구간마다 클립이 빈틈없이 맞닿고 크롭이 따라가며, 뒤 클립은 남은 길이만큼 밀린다")
    func placeDerivedWithExclusions() throws {
        let editor = try makeEditor()
        let crop = ClipCrop(top: 0.1, bottom: 0, left: 0, right: 0)
        let newID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: .zero, end: seconds(10), excluded: [range(2, 3), range(5, 7)], crop: crop))
        let bRoll = try #require(videoClips(editor).first { $0.assetID == SampleData.bRollVideo.id })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let firstID = try #require(editor.placeAsset(newID, onTrack: nil, at: seconds(8)))
        undoManager.endUndoGrouping()

        let placed = videoClips(editor).filter { $0.assetID == newID }
        #expect(placed.count == 3)
        #expect(placed.first?.id == firstID)
        #expect(placed.map(\.sourceRange) == [range(0, 2), range(3, 5), range(7, 10)])
        #expect(placed.map(\.timelineStart) == [seconds(8), seconds(10), seconds(12)])
        #expect(placed.allSatisfy { $0.crop == crop })
        #expect(editor.currentSequence.clip(id: bRoll.id)?.timelineStart == seconds(15))

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("여러 항목을 한 번에 놓아도 뺀 구간이 있는 항목은 펼쳐져 이어 붙는다")
    func placeSeveralWithExclusions() throws {
        let editor = try makeEditor()
        let newID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: .zero, end: seconds(4), excluded: [range(1, 2)]))
        let placed = editor.placeAssets([newID, SampleData.bRollVideo.id], at: seconds(18))
        #expect(placed.count == 3)
        let clips = placed.compactMap { editor.currentSequence.clip(id: $0) }
        #expect(clips.map(\.timelineStart) == [seconds(18), seconds(19), seconds(21)])
    }

    // MARK: - 타임라인 클립

    @Test("클립에 구간을 빼고 적용하면 남은 구간들로 나뉘어 맞닿고, 앞 조각이 원래 ID와 전환을 지키며, 뒤 클립이 당겨진다")
    func applyToClip() throws {
        let editor = try makeEditor()
        let clips = videoClips(editor)
        let intro = clips[0]
        editor.renameClip(intro.id, to: "인트로")
        editor.setClipAudio(volume: 0.5, isMuted: false, for: intro.id)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project
        let crop = ClipCrop(top: 0, bottom: 0.2, left: 0, right: 0)

        undoManager.beginUndoGrouping()
        editor.commitClipTrim(intro.id, start: .zero, end: seconds(8), excluded: [range(1, 2), range(4, 6)], crop: crop)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "트림")

        let pieces = videoClips(editor).filter { $0.assetID == intro.assetID }
        #expect(pieces.count == 3)
        #expect(pieces[0].id == intro.id)
        #expect(Set(pieces.map(\.id)).count == 3)
        #expect(pieces.map(\.sourceRange) == [range(0, 1), range(2, 4), range(6, 8)])
        #expect(pieces.map(\.timelineStart) == [seconds(0), seconds(1), seconds(3)])
        #expect(pieces.allSatisfy { $0.name == "인트로" && $0.volume == 0.5 && $0.crop == crop })
        #expect(pieces.dropFirst().allSatisfy { $0.transitionIn == nil })
        // 8초 → 5초로 줄어든 만큼 B컷이 당겨진다.
        #expect(editor.currentSequence.clip(id: clips[1].id)?.timelineStart == seconds(5))
        #expect(editor.currentSequence.clip(id: clips[1].id)?.transitionIn == clips[1].transitionIn)

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("클립 구간을 전부 빼고 적용하면 바뀌지 않는다")
    func applyToClipNothingKept() throws {
        let editor = try makeEditor()
        let intro = videoClips(editor)[0]
        let before = editor.project
        editor.commitClipTrim(intro.id, start: .zero, end: seconds(8), excluded: [range(0, 8)])
        #expect(editor.project == before)
    }

    // MARK: - 저장

    @Test("뺀 구간을 가진 파생 항목은 저장했다가 그대로 불러온다")
    func persistence() throws {
        let editor = try makeEditor()
        _ = editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(1), end: seconds(9), excluded: [range(2, 3), range(5, 6.5)])
        try editor.save()

        let loaded = try #require(try repository.project(id: editor.project.id))
        #expect(loaded == editor.project)
        #expect(loaded.assets.contains { $0.excludedRanges == [range(2, 3), range(5, 6.5)] })
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

    private func range(_ start: Double, _ end: Double) -> CMTimeRange {
        CMTimeRange(start: seconds(start), end: seconds(end))
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
