import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 트림 시트(#81): 미디어 패널 항목의 파생 항목 만들기(새 항목으로 저장·자르기)·파생 구간 적용, 타임라인 클립 트림·자르기. 원본 항목은 바뀌지 않는다.
/// 샘플: 인트로 원본(10초, "촬영본" 폴더 첫 항목), 영상 트랙 인트로 클립 0~8초(원본 0~8초)·B컷 8~18초.
@MainActor
struct TrimSheetTests {
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

    // MARK: - 원본(미디어 패널)

    @Test("방향키 이동은 잡은 끝을 0.1초·1초씩 옮기고, 원본 범위와 최소 길이 안으로 맞춘다")
    func nudgeRange() {
        let range = CMTimeRange(start: seconds(2), end: seconds(10))
        let duration = seconds(12)
        #expect(TrimRange.nudging(range, edge: .start, by: TrimRange.smallStep, sourceDuration: duration) == CMTimeRange(start: seconds(2.1), end: seconds(10)))
        #expect(TrimRange.nudging(range, edge: .end, by: CMTime.zero - TrimRange.largeStep, sourceDuration: duration) == CMTimeRange(start: seconds(2), end: seconds(9)))
        // 원본 밖으로 나가지 않는다.
        #expect(TrimRange.nudging(range, edge: .start, by: seconds(-5), sourceDuration: duration).start == .zero)
        #expect(TrimRange.nudging(range, edge: .end, by: seconds(5), sourceDuration: duration).end == duration)
        // 반대쪽 끝을 넘지 않고 최소 길이는 남는다.
        let squeezed = TrimRange.nudging(range, edge: .start, by: seconds(20), sourceDuration: duration)
        #expect(squeezed.end == seconds(10) && squeezed.duration == Clip.minimumDuration)
        #expect(TrimRange.nudging(range, edge: .start, by: .zero, sourceDuration: duration) == range)
    }

    @Test("원본 항목은 트림으로 바뀌지 않고, 파생 항목은 놓을 때 그 구간만 클립이 되며, 그 클립도 원본 전체까지 다시 늘릴 수 있다")
    func derivedRangeAppliesToPlacement() throws {
        let editor = try makeEditor()
        let original = SampleData.introVideo
        let derivedID = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(2), end: seconds(6)))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager

        // 원본 항목은 "적용"으로 바뀌지 않는다.
        undoManager.beginUndoGrouping()
        editor.setUsedRange(start: seconds(1), end: seconds(3), for: original.id)
        undoManager.endUndoGrouping()
        #expect(editor.asset(id: original.id) == original)

        // 파생 항목은 자기 구간을 바꿀 수 있다.
        undoManager.beginUndoGrouping()
        editor.setUsedRange(start: seconds(2), end: seconds(5), for: derivedID)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "트림")
        #expect(editor.asset(id: derivedID)?.usedRange == CMTimeRange(start: seconds(2), end: seconds(5)))
        #expect(editor.asset(id: derivedID)?.placementDuration == seconds(3))

        undoManager.beginUndoGrouping()
        let clipID = try #require(editor.placeAsset(derivedID, onTrack: nil, at: seconds(18)))
        undoManager.endUndoGrouping()
        #expect(editor.currentSequence.clip(id: clipID)?.sourceRange == CMTimeRange(start: seconds(2), end: seconds(5)))

        // 비파괴: 놓은 클립을 끝까지 늘리면 원본 전체 범위까지 간다.
        undoManager.beginUndoGrouping()
        editor.trimClip(clipID, edge: .end, by: seconds(100))
        editor.trimClip(clipID, edge: .start, by: seconds(-100))
        undoManager.endUndoGrouping()
        #expect(editor.currentSequence.clip(id: clipID)?.sourceRange == CMTimeRange(start: .zero, duration: original.duration))
    }

    @Test("파생 항목 구간은 원본 범위로 맞추고, 원본 전체가 되면 구간이 없어진다(파생 표시는 남는다). 이미지는 트림하지 않는다")
    func derivedRangeClamp() throws {
        let editor = try makeEditor()
        let duration = SampleData.introVideo.duration
        let derivedID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(-3), end: seconds(5)))
        #expect(editor.asset(id: derivedID)?.usedRange == CMTimeRange(start: .zero, end: seconds(5)))

        editor.setUsedRange(start: .zero, end: duration + seconds(1), for: derivedID)
        #expect(editor.asset(id: derivedID)?.usedRange == nil)
        #expect(editor.asset(id: derivedID)?.isDerived == true)

        #expect(SampleData.introVideo.isTrimmable && !SampleData.introVideo.isDerived)
        let image = MediaAsset(id: UUID(), name: "logo.png", sourceURL: URL(filePath: "/tmp/logo.png"), kind: .image, duration: MediaAsset.stillImageDuration)
        #expect(!image.isTrimmable)
    }

    @Test("새 항목으로 저장하면 같은 파일을 가리키는 파생 항목이 원본 바로 뒤(같은 폴더)에 구간과 함께 생기고, 원본은 그대로다")
    func addTrimmedAsset() throws {
        let editor = try makeEditor()
        let original = SampleData.introVideo
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let newID = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(3), end: seconds(7)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "새 항목으로 저장")

        let added = try #require(editor.asset(id: newID))
        #expect(added.id != original.id && added.isDerived)
        #expect(added.sourceURL == original.sourceURL && added.bookmarkData == original.bookmarkData && added.kind == original.kind)
        #expect(added.usedRange == CMTimeRange(start: seconds(3), end: seconds(7)))
        // 썸네일·파형·프록시는 원본 것을 같이 쓴다.
        #expect(added.mediaKey == original.mediaKey)
        #expect(editor.asset(id: original.id) == original)
        let folder = try #require(editor.project.folders.first { $0.assetIDs.contains(original.id) })
        let index = try #require(folder.assetIDs.firstIndex(of: original.id))
        #expect(folder.assetIDs[index + 1] == newID)

        // 원본 항목을 지워도 파생 항목은 남는다.
        undoManager.beginUndoGrouping()
        editor.deleteAssets([original.id])
        undoManager.endUndoGrouping()
        #expect(editor.asset(id: newID) != nil)

        undoManager.undo()
        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("파생 항목 이름은 처음 원본 이름에 구간을 붙이고, 같은 이름이 있으면 번호를 붙이며, 파생에서 또 만들어도 쌓이지 않는다")
    func derivedNames() throws {
        let editor = try makeEditor()
        let original = SampleData.introVideo

        let first = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(2), end: seconds(7)))
        #expect(editor.asset(id: first)?.name == "intro (0:02.0–0:07.0).mov")
        let same = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(2), end: seconds(7)))
        #expect(editor.asset(id: same)?.name == "intro (0:02.0–0:07.0) (1).mov")
        let again = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(2), end: seconds(7)))
        #expect(editor.asset(id: again)?.name == "intro (0:02.0–0:07.0) (2).mov")

        // 파생 항목에서 만들어도 처음 원본 이름 기준이다.
        let nested = try #require(editor.addTrimmedAsset(from: first, start: seconds(3), end: seconds(4.5)))
        #expect(editor.asset(id: nested)?.name == "intro (0:03.0–0:04.5).mov")
        #expect(editor.asset(id: nested)?.mediaKey == original.mediaKey)
    }

    @Test("항목을 자르면 바꿔 둔 구간을 반영해 앞·뒤 두 파생 항목을 만들고, 재생 위치가 구간 밖이면 아무것도 하지 않는다")
    func splitAsset() throws {
        let editor = try makeEditor()
        let original = SampleData.introVideo
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager

        #expect(editor.splitAsset(original.id, start: seconds(2), end: seconds(10), at: seconds(11)) == nil)
        undoManager.beginUndoGrouping()
        let pieces = try #require(editor.splitAsset(original.id, start: seconds(2), end: seconds(10), at: seconds(6)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "자르기")

        #expect(editor.asset(id: pieces.front)?.usedRange == CMTimeRange(start: seconds(2), end: seconds(6)))
        #expect(editor.asset(id: pieces.back)?.usedRange == CMTimeRange(start: seconds(6), end: seconds(10)))
        #expect(editor.asset(id: pieces.front)?.name == "intro (0:02.0–0:06.0).mov")
        #expect(editor.asset(id: pieces.back)?.name == "intro (0:06.0–0:10.0).mov")
        #expect(editor.asset(id: pieces.front)?.mediaKey == original.mediaKey)
        #expect(editor.asset(id: original.id) == original)
    }

    // MARK: - 타임라인 클립

    @Test("클립 트림(적용)은 원본 범위 안에서 리플로 반영하고, 원본 항목의 구간은 바꾸지 않는다")
    func commitClipTrim() throws {
        let editor = try makeEditor()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let clips = videoClips(editor)
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.commitClipTrim(clips[0].id, start: seconds(1), end: seconds(20))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "트림")

        let trimmed = try #require(editor.currentSequence.clip(id: clips[0].id))
        // 원본(10초)을 넘지 않는다.
        #expect(trimmed.sourceRange == CMTimeRange(start: seconds(1), end: SampleData.introVideo.duration))
        #expect(trimmed.timelineStart == .zero)
        // 뒤 클립이 따라온다(리플).
        #expect(editor.currentSequence.clip(id: clips[1].id)?.timelineStart == trimmed.timelineRange.end)
        #expect(editor.asset(id: SampleData.introVideo.id)?.usedRange == nil)

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("클립 자르기는 바꿔 둔 구간을 반영하고 재생 위치(원본 시각)에서 나누며, 두 조각이 같은 속성을 갖고 실행 취소 한 번으로 돌아온다")
    func splitClipWithRange() throws {
        let editor = try makeEditor()
        let clip = videoClips(editor)[0]
        editor.renameClip(clip.id, to: "인트로")
        editor.setColorAdjustment(ColorAdjustment(saturation: 0), for: [clip.id])
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        #expect(!editor.splitClip(clip.id, start: seconds(2), end: seconds(6), at: seconds(7)))
        #expect(editor.splitClip(clip.id, start: seconds(2), end: seconds(6), at: seconds(4)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "자르기")

        let pieces = videoClips(editor).filter { $0.assetID == clip.assetID }
        #expect(pieces.count == 2)
        #expect(pieces[0].id == clip.id)
        #expect(pieces[0].sourceRange == CMTimeRange(start: seconds(2), end: seconds(4)))
        #expect(pieces[1].sourceRange == CMTimeRange(start: seconds(4), end: seconds(6)))
        #expect(pieces[1].timelineStart == pieces[0].timelineRange.end)
        #expect(pieces.allSatisfy { $0.name == "인트로" && $0.colorAdjustment == ColorAdjustment(saturation: 0) })

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("파생 항목(구간·처음 원본 표시)은 저장했다가 그대로 불러온다")
    func persistence() throws {
        let editor = try makeEditor()
        _ = editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(2), end: seconds(6))
        _ = editor.addTrimmedAsset(from: SampleData.bRollVideo.id, start: seconds(1), end: seconds(3))

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

    private func videoClips(_ editor: ProjectEditor) -> [Clip] {
        editor.currentSequence.tracks.first { $0.kind == .video }?.clips ?? []
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
