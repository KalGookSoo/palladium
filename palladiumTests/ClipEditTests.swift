import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 클립 편집 창의 크롭(#85): 범위 맞추기·끌기·비율 프리셋 규칙.
struct ClipCropTests {
    private let landscape = CGSize(width: 1920, height: 1080)

    @Test("크롭은 0~1 범위로 맞추고, 남는 폭·높이는 10% 아래로 줄지 않는다")
    func clamp() {
        var crop = ClipCrop(top: -0.2, bottom: 0.95, left: 0.6, right: 0.6)
        crop.clamp()
        #expect(crop.top == 0)
        #expect(abs(crop.bottom - 0.9) < 1e-9)
        #expect(crop.left == 0.6)
        #expect(abs(crop.right - 0.3) < 1e-9)

        // 끝이 없는 값(NaN·무한대)은 0으로 본다.
        var invalid = ClipCrop(top: .nan, bottom: .infinity, left: 0, right: 0)
        invalid.clamp()
        #expect(invalid == ClipCrop())
        #expect(ClipCrop().isDefault)
    }

    @Test("자유 끌기는 잡은 변만 옮기고 반대쪽은 그대로 두며, 원본 밖이나 최소 크기를 넘지 않는다")
    func freeDrag() {
        let left = ClipCrop().dragging(.left, to: CGPoint(x: 0.3, y: 0.9), aspectRatio: nil, contentSize: landscape)
        expect(left, ClipCrop(top: 0, bottom: 0, left: 0.3, right: 0))
        // 오른쪽 변을 왼쪽 변 너머로 끌어도 최소 폭(10%)은 남는다.
        let squeezed = left.dragging(.right, to: CGPoint(x: 0.1, y: 0.5), aspectRatio: nil, contentSize: landscape)
        expect(squeezed, ClipCrop(top: 0, bottom: 0, left: 0.3, right: 0.6))
        // 모서리는 두 변을 함께 옮기고, 원본 밖으로 나가지 않는다.
        let corner = ClipCrop().dragging(.topLeft, to: CGPoint(x: -0.5, y: 0.2), aspectRatio: nil, contentSize: landscape)
        expect(corner, ClipCrop(top: 0.2, bottom: 0, left: 0, right: 0))
    }

    @Test("비율을 지키는 끌기(⇧·프리셋): 모서리는 반대 모서리를 기준으로, 변은 다른 방향 가운데를 지키며 비율을 맞춘다")
    func lockedDrag() throws {
        let corner = ClipCrop().dragging(.bottomRight, to: CGPoint(x: 0.5, y: 0.9), aspectRatio: 16.0 / 9, contentSize: landscape)
        #expect(corner.left == 0 && corner.top == 0)
        #expect(try abs(#require(corner.aspectRatio(contentSize: landscape)) - 16.0 / 9) < 1e-6)
        #expect(abs(corner.visibleRect.width - 0.9) < 1e-9)

        let edge = ClipCrop().dragging(.right, to: CGPoint(x: 0.5, y: 0.1), aspectRatio: 1, contentSize: landscape)
        #expect(try abs(#require(edge.aspectRatio(contentSize: landscape)) - 1) < 1e-6)
        #expect(edge.left == 0 && abs(edge.visibleRect.width - 0.5) < 1e-9)
        #expect(abs(edge.visibleRect.midY - 0.5) < 1e-9)

        // 원본 높이를 넘는 만큼은 늘어나지 않는다(1:1이면 폭은 원본 높이만큼까지).
        let capped = ClipCrop().dragging(.right, to: CGPoint(x: 1, y: 0.5), aspectRatio: 1, contentSize: landscape)
        #expect(abs(capped.visibleRect.width - 1080.0 / 1920) < 1e-9 && abs(capped.visibleRect.height - 1) < 1e-9)
    }

    @Test("비율 프리셋은 지금 영역의 가운데를 지키며 원본 안에 들어가는 가장 큰 사각형으로 맞춘다")
    func presets() throws {
        let square = try ClipCrop().fitted(toAspectRatio: #require(CropAspect.square1x1.ratio(contentSize: landscape)), contentSize: landscape)
        #expect(abs(square.visibleRect.width - 1080.0 / 1920) < 1e-9 && abs(square.visibleRect.height - 1) < 1e-9)
        #expect(abs(square.visibleRect.midX - 0.5) < 1e-9)

        for aspect in [CropAspect.landscape16x9, .portrait9x16, .portrait4x5] {
            let ratio = try #require(aspect.ratio(contentSize: landscape))
            let fitted = ClipCrop(top: 0, bottom: 0, left: 0.6, right: 0).fitted(toAspectRatio: ratio, contentSize: landscape)
            #expect(try abs(#require(fitted.aspectRatio(contentSize: landscape)) - ratio) < 1e-6)
            // 원본 밖으로 나가지 않는다.
            #expect(fitted.left >= -1e-9 && fitted.right >= -1e-9)
        }
        let original = try ClipCrop(top: 0.1, bottom: 0, left: 0, right: 0.3).fitted(toAspectRatio: #require(CropAspect.original.ratio(contentSize: landscape)), contentSize: landscape)
        #expect(abs(original.visibleRect.width - 1) < 1e-9 && abs(original.visibleRect.height - 1) < 1e-9)
        #expect(CropAspect.free.ratio(contentSize: landscape) == nil)
    }

    @Test("숫자 입력은 그 변만 바꾸고, 반대쪽 변은 그대로 두며 최소 크기를 넘으면 이 값을 줄인다")
    func settingEdge() {
        let crop = ClipCrop(top: 0, bottom: 0.5, left: 0.1, right: 0)
        expect(crop.setting(\.top, to: 0.6), ClipCrop(top: 0.4, bottom: 0.5, left: 0.1, right: 0))
        expect(crop.setting(\.right, to: 0.2), ClipCrop(top: 0, bottom: 0.5, left: 0.1, right: 0.2))
        expect(crop.setting(\.left, to: -1), ClipCrop(top: 0, bottom: 0.5, left: 0, right: 0))
    }

    @Test("비율을 지키며 최소 크기를 남길 수 없는 가장자리에서는 끌어도 바뀌지 않는다")
    func lockedDragKeepsMinimum() {
        // 아래쪽 20%만 남긴 영역의 오른쪽 아래 모서리를 9:16으로 끌면, 높이 20% 안에서는 폭 10%를 남길 수 없다.
        let crop = ClipCrop(top: 0.8, bottom: 0, left: 0, right: 0.5)
        #expect(crop.dragging(.bottomRight, to: CGPoint(x: 0.6, y: 1), aspectRatio: 9.0 / 16, contentSize: landscape) == crop)
    }

    @Test("옮기기는 크기를 지키고 원본 밖으로 나가지 않는다")
    func move() {
        let crop = ClipCrop(top: 0.25, bottom: 0.25, left: 0.25, right: 0.25)
        expect(crop.moved(dx: 0.1, dy: -0.1), ClipCrop(top: 0.15, bottom: 0.35, left: 0.35, right: 0.15))
        expect(crop.moved(dx: 1, dy: 1), ClipCrop(top: 0.5, bottom: 0, left: 0.5, right: 0))
    }

    private func expect(_ crop: ClipCrop, _ expected: ClipCrop, sourceLocation: SourceLocation = #_sourceLocation) {
        let values = [crop.top - expected.top, crop.bottom - expected.bottom, crop.left - expected.left, crop.right - expected.right]
        #expect(values.allSatisfy { abs($0) < 1e-9 }, "\(crop) ≠ \(expected)", sourceLocation: sourceLocation)
    }
}

/// 클립 편집 창의 편집기 커맨드(#85): 크롭 적용, 파생 항목 크롭, 놓기·나누기·복사·붙여넣기에 따라가기, 저장.
/// 샘플: 인트로 원본(10초), 영상 트랙 인트로 클립 0~8초(원본 0~8초)·B컷 8~18초.
@MainActor
struct ClipEditTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository
    private let crop = ClipCrop(top: 0.1, bottom: 0.2, left: 0.05, right: 0.15)

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // 자동 저장 타이머가 테스트가 끝나 사라진 컨테이너에 불리면 앱이 멈추므로 끈다.
        container.mainContext.autosaveEnabled = false
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    @Test("클립 적용은 구간과 크롭(범위로 맞춤)을 함께 바꾸고 실행 취소 한 번에 돌아오며, 크롭을 주지 않으면 크롭은 그대로다")
    func applyCropToClip() throws {
        let editor = try makeEditor()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let clip = videoClips(editor)[0]
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.commitClipTrim(clip.id, start: seconds(1), end: seconds(5), crop: ClipCrop(top: 0.95, bottom: 0, left: -1, right: 0.2))
        undoManager.endUndoGrouping()

        let edited = try #require(editor.currentSequence.clip(id: clip.id))
        #expect(edited.sourceRange == CMTimeRange(start: seconds(1), end: seconds(5)))
        #expect(abs(edited.crop.top - 0.9) < 1e-9 && edited.crop.left == 0 && edited.crop.right == 0.2)
        // 원본 항목은 그대로다.
        #expect(editor.asset(id: SampleData.introVideo.id) == SampleData.introVideo)

        undoManager.beginUndoGrouping()
        editor.commitClipTrim(clip.id, start: seconds(1), end: seconds(4))
        undoManager.endUndoGrouping()
        #expect(editor.currentSequence.clip(id: clip.id)?.crop == edited.crop)

        undoManager.undo()
        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("새 항목으로 저장·적용은 파생 항목에 크롭을 넣고 원본 항목은 그대로이며, 파생 항목을 놓으면 클립이 구간과 크롭을 갖는다")
    func derivedAssetCrop() throws {
        let editor = try makeEditor()
        let original = SampleData.introVideo
        let derivedID = try #require(editor.addTrimmedAsset(from: original.id, start: seconds(2), end: seconds(6), crop: crop))
        #expect(editor.asset(id: derivedID)?.crop == crop)
        #expect(editor.asset(id: original.id) == original)

        // 원본 항목에는 적용되지 않는다.
        editor.setUsedRange(start: seconds(1), end: seconds(3), crop: crop, for: original.id)
        #expect(editor.asset(id: original.id) == original)

        let changed = ClipCrop(top: 0, bottom: 0, left: 0.5, right: 0)
        editor.setUsedRange(start: seconds(2), end: seconds(5), crop: changed, for: derivedID)
        #expect(editor.asset(id: derivedID)?.crop == changed)
        #expect(editor.asset(id: derivedID)?.usedRange == CMTimeRange(start: seconds(2), end: seconds(5)))

        let clipID = try #require(editor.placeAsset(derivedID, onTrack: nil, at: seconds(18)))
        let placed = try #require(editor.currentSequence.clip(id: clipID))
        #expect(placed.crop == changed)
        #expect(placed.sourceRange == CMTimeRange(start: seconds(2), end: seconds(5)))
    }

    @Test("크롭은 타임라인 나누기·복사·붙여넣기·클립 편집 창 자르기·항목 자르기에 따라간다")
    func cropFollowsEdits() throws {
        let editor = try makeEditor()
        let clip = videoClips(editor)[0]
        editor.commitClipTrim(clip.id, start: clip.sourceRange.start, end: clip.sourceRange.end, crop: crop)

        editor.splitClips([clip.id], at: seconds(4))
        let pieces = videoClips(editor).filter { $0.assetID == clip.assetID }
        #expect(pieces.count == 2 && pieces.allSatisfy { $0.crop == crop })

        editor.copyClips([pieces[0].id])
        let pasted = try #require(editor.pasteClips(at: .zero))
        guard case let .clips(pastedIDs) = pasted else {
            Issue.record("클립을 붙이지 못함")
            return
        }
        #expect(pastedIDs.allSatisfy { editor.currentSequence.clip(id: $0)?.crop == crop })

        // 클립 편집 창 "자르기"는 고친 크롭을 두 조각에 함께 넣는다.
        let changed = ClipCrop(top: 0.3, bottom: 0, left: 0, right: 0)
        #expect(editor.splitClip(pieces[0].id, start: pieces[0].sourceRange.start, end: pieces[0].sourceRange.end, crop: changed, at: seconds(2)))
        #expect(videoClips(editor).filter { $0.crop == changed }.count == 2)

        let assetPieces = try #require(editor.splitAsset(SampleData.introVideo.id, start: seconds(1), end: seconds(9), crop: crop, at: seconds(5)))
        #expect(editor.asset(id: assetPieces.front)?.crop == crop)
        #expect(editor.asset(id: assetPieces.back)?.crop == crop)
        #expect(editor.asset(id: SampleData.introVideo.id) == SampleData.introVideo)
    }

    @Test("클립·파생 항목의 크롭은 저장했다가 그대로 불러오고, 크롭이 없는 것은 자르지 않은 채로 연다")
    func persistence() throws {
        let editor = try makeEditor()
        let derivedID = try #require(editor.addTrimmedAsset(from: SampleData.introVideo.id, start: seconds(2), end: seconds(6), crop: crop))
        let clip = videoClips(editor)[0]
        editor.commitClipTrim(clip.id, start: clip.sourceRange.start, end: clip.sourceRange.end, crop: crop)

        try editor.save()
        let loaded = try #require(try repository.project(id: editor.project.id))

        #expect(loaded == editor.project)
        #expect(loaded.assets.first { $0.id == derivedID }?.crop == crop)
        #expect(loaded.sequences[0].clip(id: clip.id)?.crop == crop)
        #expect(loaded.assets.first { $0.id == SampleData.introVideo.id }?.crop.isDefault == true)
        #expect(loaded.sequences[0].clip(id: videoClips(editor)[1].id)?.crop.isDefault == true)
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
        (editor.currentSequence.tracks.first { $0.kind == .video }?.clips ?? []).sorted { $0.timelineStart < $1.timelineStart }
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}

/// 합성기의 크롭(#85): 원본을 잘라낸 뒤 잘린 화면 기준으로 위치·크기를 적용한다. 미리보기와 내보내기는 같은 합성을 쓴다.
struct ClipCropCompositionTests {
    @Test("왼쪽 빨강·오른쪽 파랑 영상에서 오른쪽을 잘라내면 빨강만 화면에 맞춰 놓이고, 위치·크기는 잘린 화면 기준이다")
    func cropsBeforePlacing() async throws {
        let url = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1, width: 160, height: 90, rightHalf: (0, 0, 255))
        let asset = MediaAsset(id: UUID(), name: "split.mov", sourceURL: url, kind: .video, duration: CMTime(value: 1, timescale: 1))

        // 위·아래 25%, 오른쪽 50%를 자르면 16:9인 빨간 영역만 남아 화면을 가득 채운다.
        var filled = try #require(asset.makeClip(at: .zero))
        filled.crop = ClipCrop(top: 0.25, bottom: 0.25, left: 0, right: 0.5)
        let full = try await frame(of: filled, asset: asset)
        for x in [0.05, 0.5, 0.95] {
            let color = TestMedia.color(of: full, atX: x, y: 0.5)
            #expect(color.red > 200 && color.blue < 60, "x=\(x): \(color)")
        }

        // 같은 크롭에 크기 0.5·가운데 (0.25, 0.5)면 잘린 화면이 왼쪽 절반 가운데에 놓이고 나머지는 검다.
        var placed = filled
        placed.transform = ClipTransform(centerX: 0.25, centerY: 0.5, scale: 0.5)
        let small = try await frame(of: placed, asset: asset)
        let inside = TestMedia.color(of: small, atX: 0.25, y: 0.5)
        let outside = TestMedia.color(of: small, atX: 0.75, y: 0.5)
        #expect(inside.red > 200 && inside.blue < 60)
        #expect(outside.red < 30 && outside.green < 30 && outside.blue < 30)

        // 크롭이 없으면 오른쪽 절반은 파랑이다.
        let uncropped = try await frame(of: #require(asset.makeClip(at: .zero)), asset: asset)
        #expect(TestMedia.color(of: uncropped, atX: 0.75, y: 0.5).blue > 200)
    }

    private func frame(of clip: Clip, asset: MediaAsset) async throws -> CGImage {
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        sequence.place(clip, onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence,
            assets: [asset],
            aspectRatio: .landscape16x9,
            resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(value: 1, timescale: 2)).image
    }
}
