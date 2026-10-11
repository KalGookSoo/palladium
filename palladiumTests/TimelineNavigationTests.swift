import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 단축키 점검(#64): 편집점 이동(↑/↓), 기본 전환(⇧⌘T), 타임라인 전체 보기(⇧Z), J/K/L 속도, 단축키 겹침 검사.
/// 샘플: 영상 트랙 인트로 0~8초·B컷 8~18초(앞 클립과 디졸브), 오디오 트랙 배경음악 0~18초.
@MainActor
struct TimelineNavigationTests {
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

    @Test("편집점은 0초와 모든 클립의 시작·끝이고, 이전·다음 편집점은 재생 헤드에 붙은 편집점을 건너뛴다")
    func editPoints() {
        let sequence = SampleData.project.sequences[0]
        #expect(sequence.editPoints.map(\.seconds) == [0, 8, 18])
        #expect(sequence.nextEditPoint(after: .zero) == seconds(8))
        #expect(sequence.nextEditPoint(after: seconds(8)) == seconds(18))
        #expect(sequence.nextEditPoint(after: seconds(18)) == nil)
        #expect(sequence.previousEditPoint(before: seconds(10)) == seconds(8))
        #expect(sequence.previousEditPoint(before: seconds(8)) == .zero)
        #expect(sequence.previousEditPoint(before: .zero) == nil)
        // 반 프레임 안쪽이면 그 편집점에 있는 것으로 본다.
        #expect(sequence.nextEditPoint(after: CMTime(value: 4799, timescale: 600)) == seconds(18))
    }

    @Test("기본 전환은 고른 클립 중 앞 클립과 맞닿은 클립에, 고른 것이 없으면 재생 헤드에서 시작하는 클립에 넣는다")
    func defaultTransitionTargets() throws {
        let sequence = SampleData.project.sequences[0]
        let video = try #require(sequence.tracks.first { $0.kind == .video }?.clips)
        // 인트로는 앞 클립이 없어 넣을 수 없다.
        #expect(sequence.defaultTransitionTargets(selected: [video[0].id], playhead: .zero).isEmpty)
        #expect(sequence.defaultTransitionTargets(selected: [video[0].id, video[1].id], playhead: .zero) == [video[1].id])
        #expect(sequence.defaultTransitionTargets(selected: [], playhead: seconds(8)) == [video[1].id])
        #expect(sequence.defaultTransitionTargets(selected: [], playhead: seconds(5)).isEmpty)
    }

    @Test("기본 전환 추가는 1초 디졸브를 넣고 실행 취소 한 번으로 돌아온다")
    func addDefaultTransitions() throws {
        let editor = try makeEditor()
        let bRoll = try #require(editor.currentSequence.tracks.first { $0.kind == .video }?.clips[1])
        editor.setTransition(nil, forClip: bRoll.id)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        #expect(editor.addDefaultTransitions(selected: [], at: seconds(8)) == 1)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "기본 전환")
        #expect(editor.currentSequence.clip(id: bRoll.id)?.transitionIn == ClipTransition(kind: .dissolve, duration: ClipTransition.defaultDuration))

        undoManager.undo()
        #expect(editor.project == before)
        #expect(editor.addDefaultTransitions(selected: [], at: seconds(3)) == 0)
    }

    @Test("전체 보기 배율은 길이 전체가 폭에 들어오게 하고, 허용 범위를 넘지 않는다")
    func fitting() {
        #expect(TimelineScale.fitting(seconds(20), into: 800).pointsPerSecond == 40)
        #expect(TimelineScale.fitting(seconds(0.5), into: 800).pointsPerSecond == TimelineScale.maximumPointsPerSecond)
        #expect(TimelineScale.fitting(seconds(3600), into: 800).pointsPerSecond == TimelineScale.minimumPointsPerSecond)
        #expect(TimelineScale.fitting(.zero, into: 800).pointsPerSecond == 40)
    }

    @Test("J/L은 같은 쪽을 다시 누를수록 2배·4배로, 반대쪽은 그쪽 1배로 바뀐다")
    func shuttleRate() {
        #expect(ShuttleRate.next(from: 0, forward: true) == 1)
        #expect(ShuttleRate.next(from: 1, forward: true) == 2)
        #expect(ShuttleRate.next(from: 2, forward: true) == 4)
        #expect(ShuttleRate.next(from: 4, forward: true) == 4)
        #expect(ShuttleRate.next(from: 2, forward: false) == -1)
        #expect(ShuttleRate.next(from: -1, forward: false) == -2)
        #expect(ShuttleRate.next(from: -4, forward: true) == 1)
    }

    @Test("단축키 목록의 키는 서로 겹치지 않는다")
    func shortcutsAreUnique() {
        let keys = ShortcutGuide.sections.flatMap(\.entries).compactMap(\.keys)
        let duplicates = Dictionary(grouping: keys, by: \.self).filter { $1.count > 1 }.keys
        #expect(duplicates.isEmpty, "겹치는 단축키: \(duplicates.sorted())")
        let titles = ShortcutGuide.sections.flatMap(\.entries).map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test("한 글자 단축키 메뉴 이름은 이름 뒤에 키를 붙인다")
    func menuTitle() {
        #expect(ShortcutGuide.addMarker.menuTitle == "재생 헤드에 마커 추가 (M)")
        #expect(ShortcutGuide.aspectRatio.menuTitle == "화면비")
    }

    // MARK: - Helpers

    private func makeEditor() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
