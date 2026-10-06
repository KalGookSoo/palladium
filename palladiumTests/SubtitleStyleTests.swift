import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 자막 자유 위치와 글꼴·색·배경·불투명도(#82).
@MainActor
struct SubtitleStyleTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository
    private let render = CGSize(width: 1920, height: 1080)

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // 자동 저장 타이머가 테스트가 끝나 사라진 컨테이너에 불리면 앱이 멈추므로 끈다.
        container.mainContext.autosaveEnabled = false
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    // MARK: - 도메인

    @Test("범위 밖 값은 맞추고, 빠른 위치(위·가운데·아래)는 가로 가운데·그 높이로 옮긴다")
    func clampAndPresets() {
        var style = SubtitleStyle(
            fontSize: 500, centerX: -1, centerY: 3, fontName: "",
            textColor: SubtitleRGB(red: 2, green: -1, blue: 0.5), textOpacity: 7,
            backgroundColor: .black, backgroundOpacity: -1
        )
        style.clamp()
        #expect(style.fontSize == SubtitleStyle.fontSizeRange.upperBound)
        #expect(style.centerX == 0 && style.centerY == 1)
        #expect(style.fontName == SubtitleStyle.defaultFontName)
        #expect(style.textColor == SubtitleRGB(red: 1, green: 0, blue: 0.5))
        #expect(style.textOpacity == 1 && style.backgroundOpacity == 0)

        style.move(to: .top)
        #expect(style.centerX == 0.5 && style.centerY == 0 && style.preset == .top)
        style.centerX = 0.3
        #expect(style.preset == nil)
        #expect(SubtitleStyle().preset == .bottom)
    }

    @Test("상자는 위치 좌표에 가운데를 두되 가장자리 여백 안으로 맞춰, 위·아래 빠른 위치는 예전처럼 여백에 붙고 화면 밖으로 나가지 않는다")
    func boxPlacement() {
        let box = CGSize(width: 400, height: 100)
        // 1080 × 6% ≈ 65, 1920 × 5% = 96.
        let marginY: CGFloat = 65
        let marginX: CGFloat = 96

        // 예전 위치와 같다: 아래는 아래 여백, 위는 위 여백, 가운데는 화면 가운데.
        #expect(SubtitleStyle(centerY: 1).boxOrigin(boxSize: box, renderSize: render) == CGPoint(x: 760, y: render.height - marginY - 100))
        #expect(SubtitleStyle(centerY: 0).boxOrigin(boxSize: box, renderSize: render).y == marginY)
        #expect(SubtitleStyle(centerY: 0.5).boxOrigin(boxSize: box, renderSize: render) == CGPoint(x: 760, y: 490))

        // 자유 위치: 가운데를 그 자리에 둔다.
        #expect(SubtitleStyle(centerX: 0.25, centerY: 0.3).boxOrigin(boxSize: box, renderSize: render) == CGPoint(x: 280, y: 274))
        // 왼쪽 끝으로 보내도 여백 안에 머문다.
        #expect(SubtitleStyle(centerX: 0, centerY: 0.5).boxOrigin(boxSize: box, renderSize: render).x == marginX)
        // 화면보다 넓은 상자는 가운데에 둔다.
        #expect(SubtitleStyle(centerX: 0).boxOrigin(boxSize: CGSize(width: 1900, height: 100), renderSize: render).x == 10)
    }

    // MARK: - 편집기

    @Test("자막 위치 커맨드는 0~1로 맞추고 실행 취소 한 번으로 되돌리며, 방향키 이동은 실제로 보이는 자리에서 시작한다")
    func positionCommands() throws {
        let editor = try makeEditor()
        let subtitle = try #require(editor.currentSequence.subtitles.first)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.setSubtitlePosition(subtitle.id, centerX: 1.4, centerY: 0.25)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "자막 위치")
        let moved = try #require(editor.currentSequence.subtitles.first { $0.id == subtitle.id })
        #expect(moved.style.centerX == 1 && moved.style.centerY == 0.25)
        undoManager.undo()
        #expect(editor.project == before)

        // 아래 빠른 위치(여백에 붙음)에서 ↑ 한 번이면 바로 위로 움직인다.
        undoManager.beginUndoGrouping()
        editor.updateSubtitle(subtitle.id, text: subtitle.text, style: SubtitleStyle(centerY: 1))
        undoManager.endUndoGrouping()
        let bottom = try #require(editor.currentSequence.subtitles.first { $0.id == subtitle.id })
        let shownBefore = try #require(SubtitleRenderer.frame(for: bottom, renderSize: render))
        undoManager.beginUndoGrouping()
        editor.nudgeSubtitle(subtitle.id, dx: 0, dy: -0.005, renderSize: render)
        undoManager.endUndoGrouping()
        let nudged = try #require(editor.currentSequence.subtitles.first { $0.id == subtitle.id })
        let shownAfter = try #require(SubtitleRenderer.frame(for: nudged, renderSize: render))
        #expect(shownAfter.minY < shownBefore.minY)
        #expect(abs(shownAfter.midX - shownBefore.midX) < 1)
    }

    @Test("자막 스타일 편집은 글꼴·색·불투명도를 범위로 맞춰 저장하고, 저장·불러오기에 유지된다")
    func styleCommandsAndPersistence() throws {
        let editor = try makeEditor()
        let subtitle = try #require(editor.currentSequence.subtitles.first)
        let style = SubtitleStyle(
            fontSize: 40, centerX: 0.2, centerY: 0.3, fontName: "Helvetica-Bold",
            textColor: SubtitleRGB(red: 0.1, green: 0.2, blue: 0.3), textOpacity: 0.7,
            backgroundColor: SubtitleRGB(red: 0, green: 0.5, blue: 0), backgroundOpacity: 2
        )

        editor.updateSubtitle(subtitle.id, text: "안녕", style: style)

        let edited = try #require(editor.currentSequence.subtitles.first { $0.id == subtitle.id })
        var expected = style
        expected.backgroundOpacity = 1
        #expect(edited.style == expected)
        try editor.save()
        #expect(try repository.project(id: editor.project.id) == editor.project)
    }

    @Test("#82 전에 저장한 자막 스타일은 같은 모습으로 옮겨 연다(위치·노란색·배경 없음)")
    func legacyStyleMigration() {
        let legacy = SubtitleRecord.legacyStyle(fontSize: 72, position: "top", color: "yellow", hasBackground: false)
        #expect(legacy.fontSize == 72)
        #expect(legacy.preset == .top)
        #expect(legacy.textColor == .yellow)
        #expect(legacy.backgroundOpacity == 0)
        #expect(legacy.fontName == SubtitleStyle.defaultFontName)

        let defaults = SubtitleRecord.legacyStyle(fontSize: 54, position: "bottom", color: "white", hasBackground: true)
        #expect(defaults == SubtitleStyle())
    }

    // MARK: - 그리기

    @Test("이 Mac에 없는 글꼴은 기본 글꼴로 그리고, 상자 자리는 그린 이미지와 같다")
    func fontFallbackAndFrame() throws {
        #expect(SubtitleRenderer.isFontAvailable(SubtitleStyle.defaultFontName))
        #expect(!SubtitleRenderer.isFontAvailable("NoSuchFont-Regular"))
        let base = Subtitle(id: UUID(), range: CMTimeRange(start: .zero, duration: seconds(1)), text: "안녕하세요")
        var missing = base
        missing.style.fontName = "NoSuchFont-Regular"

        let defaultFrame = try #require(SubtitleRenderer.frame(for: base, renderSize: render))
        #expect(SubtitleRenderer.frame(for: missing, renderSize: render) == defaultFrame)
        // Core Image 좌표(왼쪽 아래 원점)로 뒤집으면 이미지 자리와 같다.
        let extent = try #require(SubtitleRenderer.image(for: base, renderSize: render)).extent
        #expect(extent.minX == defaultFrame.minX && extent.width == defaultFrame.width)
        #expect(extent.minY == render.height - defaultFrame.maxY)
    }

    @Test("자유 위치·글자색·배경색·불투명도가 합성(미리보기·내보내기 공통)에 그대로 그려진다")
    func composedPixels() async throws {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let subtitleID = sequence.addSubtitle(at: .zero, text: "■")
        sequence.updateSubtitle(subtitleID, text: "■", style: SubtitleStyle(
            fontSize: 120, centerX: 0.25, centerY: 0.3,
            textColor: SubtitleRGB(red: 1, green: 0, blue: 0), backgroundColor: SubtitleRGB(red: 0, green: 1, blue: 0), backgroundOpacity: 1
        ))
        let subtitle = try #require(sequence.subtitles.first)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: seconds(1)).image
        let renderSize = SequenceComposer.renderSize(for: .landscape16x9)
        let box = try #require(SubtitleRenderer.frame(for: subtitle, renderSize: renderSize))

        // 상자 가운데(글자)는 빨강, 상자 왼쪽 여백은 초록, 상자 밖은 검정.
        let glyph = TestMedia.color(of: frame, atX: box.midX / renderSize.width, y: box.midY / renderSize.height)
        #expect(glyph.red > 200 && glyph.green < 60)
        let background = TestMedia.color(of: frame, atX: (box.minX + 4) / renderSize.width, y: box.midY / renderSize.height)
        #expect(background.green > 200 && background.red < 60)
        let outside = TestMedia.color(of: frame, atX: 0.8, y: 0.8)
        #expect(outside.red < 30 && outside.green < 30)
        // 상자는 화면 왼쪽 위 사분면(가로 25%·세로 30% 근처)에 있다.
        #expect(abs(box.midX / renderSize.width - 0.25) < 0.01 && abs(box.midY / renderSize.height - 0.3) < 0.01)
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
