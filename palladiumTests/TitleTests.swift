import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 타이틀(#76): 추가·편집·페이드·복사, 합성(미리보기·내보내기 공통)에서 글자 그리기, 저장.
/// 샘플: 영상 트랙 인트로 0~8초·B컷 8~18초, 오디오 트랙 배경음악.
@MainActor
struct TitleTests {
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

    @Test("타이틀 추가는 맨 위 영상 트랙의 재생 헤드 경계에 5초 타이틀을 넣고 뒤 클립을 민다. 실행 취소 한 번으로 돌아온다")
    func addTitle() throws {
        let editor = try makeEditor()
        let overlay = editor.addTrack(kind: .video)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        let titleID = try #require(editor.addTitle(at: seconds(2)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "타이틀 추가")

        let clip = try #require(editor.currentSequence.clip(id: titleID))
        #expect(editor.currentSequence.trackID(containing: titleID) == overlay)
        #expect(clip.isTitle && clip.title == TitleText() && clip.assetID == Clip.titleAssetID)
        #expect(clip.timelineRange == CMTimeRange(start: seconds(2), duration: TitleText.defaultDuration))

        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("영상 트랙이 하나도 없으면 영상 트랙을 만들어 넣고, 영상 트랙이 하나면 그 트랙(메인) 경계에 끼워 뒤 클립을 민다")
    func addTitleTrackRules() throws {
        let created = try repository.createProject(named: "빈 프로젝트")
        let editor = ProjectEditor(project: created, repository: repository)
        let titleID = try #require(editor.addTitle(at: .zero))
        #expect(editor.currentSequence.tracks.count == 1 && editor.currentSequence.tracks[0].kind == .video)
        #expect(editor.currentSequence.clip(id: titleID) != nil)

        let sample = try makeEditor()
        let intro = try #require(sample.currentSequence.tracks.first?.clips.first)
        let opening = try #require(sample.addTitle(at: .zero))
        #expect(sample.currentSequence.clip(id: opening)?.timelineStart == .zero)
        #expect(sample.currentSequence.clip(id: intro.id)?.timelineStart == TitleText.defaultDuration)
    }

    @Test("타이틀 편집은 범위로 맞추고 빈 글자는 \"제목\"이 되며, 타이틀이 아닌 클립은 바꾸지 않는다")
    func setTitle() throws {
        let editor = try makeEditor()
        let titleID = try #require(editor.addTitle(at: seconds(18)))
        var title = TitleText(text: "  ", fontSize: 999, outlineWidth: -3, backgroundOpacity: 2)
        editor.setTitle(title, for: titleID)
        let saved = try #require(editor.currentSequence.clip(id: titleID)?.title)
        #expect(saved.text == "제목" && saved.fontSize == TitleText.fontSizeRange.upperBound && saved.outlineWidth == 0 && saved.backgroundOpacity == 1)

        let intro = try #require(editor.currentSequence.tracks.first?.clips.first)
        title.text = "바꾸면 안 됨"
        editor.setTitle(title, for: intro.id)
        #expect(editor.currentSequence.clip(id: intro.id)?.title == nil)
    }

    @Test("페이드 인·아웃은 불투명도 키프레임 네 개(0 → 1 → 1 → 0)를 두고, 트랜스폼 키프레임이 있으면 넣지 않는다")
    func fade() throws {
        let editor = try makeEditor()
        let titleID = try #require(editor.addTitle(at: seconds(18)))
        editor.addFade(to: titleID)
        let clip = try #require(editor.currentSequence.clip(id: titleID))
        #expect(clip.animation.transform.map(\.value.opacity) == [0, 1, 1, 0])
        #expect(clip.keyframeTimes(of: .transform) == [seconds(18), seconds(18.5), seconds(22.5), seconds(23)])
        #expect(abs(clip.transform(atTimeline: seconds(18.25)).opacity - 0.5) < 1e-9)

        let animated = clip.animation
        editor.addFade(to: titleID)
        #expect(editor.currentSequence.clip(id: titleID)?.animation == animated)
    }

    @Test("타이틀은 원본이 없어도 복사·붙여넣기·복제된다")
    func copyPaste() throws {
        let editor = try makeEditor()
        let titleID = try #require(editor.addTitle(at: seconds(18)))
        editor.setTitle(TitleText(text: "오프닝"), for: titleID)
        editor.copyClips([titleID])
        let pasted = editor.pasteClips(at: seconds(30))
        guard case let .clips(ids) = pasted, let pastedID = ids.first else {
            Issue.record("붙여넣지 못했다")
            return
        }
        #expect(editor.currentSequence.clip(id: pastedID)?.title?.text == "오프닝")
        #expect(editor.duplicateClips([titleID]).count == 1)
    }

    @Test("합성은 타이틀 글자를 그 자리에 그리고, 배경 상자·위치·배율을 따른다")
    func composition() async throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        // 0~2초: 화면 가운데 빨간 배경 상자의 흰 글자. 2~4초: 왼쪽 위로 옮긴 같은 타이틀.
        var title = TitleText(text: "■■", fontSize: 200, hasShadow: false, backgroundColor: SubtitleRGB(red: 1, green: 0, blue: 0), backgroundOpacity: 1)
        title.clamp()
        var centered = try #require(Clip.makeTitle(title, at: .zero))
        centered.sourceRange = CMTimeRange(start: .zero, duration: seconds(2))
        sequence.place(centered, onTrack: trackID)
        var moved = try #require(Clip.makeTitle(title, at: seconds(2)))
        moved.sourceRange = CMTimeRange(start: .zero, duration: seconds(2))
        moved.transform = ClipTransform(centerX: 0.25, centerY: 0.25, scale: 0.5)
        sequence.place(moved, onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let first = try await generator.image(at: seconds(1)).image
        let size = TitleRenderer.naturalSize(of: title, renderSize: CGSize(width: 1920, height: 1080))
        // 글자(흰색) 가운데, 상자 안 여백(빨강), 상자 밖(검정).
        let text = TestMedia.color(of: first, atX: 0.5 - size.width / 1920 * 0.25, y: 0.5)
        #expect(text.red > 200 && text.green > 200 && text.blue > 200)
        let padding = TestMedia.color(of: first, atX: 0.5, y: 0.5 - size.height / 1080 / 2 + 0.01)
        #expect(padding.red > 200 && padding.green < 60)
        let outside = TestMedia.color(of: first, atX: 0.05, y: 0.05)
        #expect(outside.red < 30)

        let second = try await generator.image(at: seconds(3)).image
        #expect(TestMedia.color(of: second, atX: 0.25, y: 0.25 - size.height / 1080 / 4 + 0.005).red > 200)
        #expect(TestMedia.color(of: second, atX: 0.5, y: 0.5).red < 30)
    }

    @Test("타이틀(글자·모양)은 저장했다가 그대로 불러온다")
    func persistence() throws {
        let editor = try makeEditor()
        let titleID = try #require(editor.addTitle(at: seconds(18)))
        editor.setTitle(TitleText(
            text: "여행\n첫날", fontName: "Helvetica-Bold", fontSize: 150, textColor: .yellow, outlineWidth: 4,
            outlineColor: SubtitleRGB(red: 0.2, green: 0.3, blue: 0.4), hasShadow: false, backgroundColor: .white, backgroundOpacity: 0.5
        ), for: titleID)
        try editor.save()

        let loaded = try #require(try repository.project(id: editor.project.id))
        #expect(loaded == editor.project)
        #expect(loaded.sequences[0].clip(id: titleID)?.title?.text == "여행\n첫날")
    }

    @Test("원래 크기 배치는 화면에 맞춰 늘리지 않고 배율만 곱해 가운데에 놓는다")
    func naturalFrame() {
        let frame = ClipTransform(centerX: 0.5, centerY: 0.25, scale: 2).frame(naturalSize: CGSize(width: 100, height: 50), in: CGSize(width: 1000, height: 800))
        #expect(frame == CGRect(x: 400, y: 150, width: 200, height: 100))
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
