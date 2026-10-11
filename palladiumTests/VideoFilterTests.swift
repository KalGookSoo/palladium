import AVFoundation
import CoreImage
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 필터형 영상 이펙트(#68): 목록 편집, 여러 클립 일괄 적용, 합성(미리보기·내보내기 공통) 픽셀, 저장.
@MainActor
struct VideoFilterTests {
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

    @Test("필터 순서는 한 칸씩 옮기고, 세기는 0~1로 맞추며, 필터가 있으면 이펙트 표시가 켜진다")
    func listRules() throws {
        let blur = VideoFilter(kind: .blur)
        let sepia = VideoFilter(kind: .sepia)
        let vignette = VideoFilter(kind: .vignette)
        let list = [blur, sepia, vignette]
        #expect(list.moving(sepia.id, by: -1).map(\.kind) == [.sepia, .blur, .vignette])
        #expect(list.moving(blur.id, by: -1) == list)
        #expect(list.moving(vignette.id, by: 1) == list)

        var filter = VideoFilter(kind: .bloom, intensity: 3)
        filter.clamp()
        #expect(filter.intensity == 1)

        var clip = try #require(Clip(assetID: UUID(), sourceRange: CMTimeRange(start: .zero, duration: seconds(1)), timelineStart: .zero))
        #expect(!clip.hasEffect)
        clip.filters = [blur]
        #expect(clip.hasEffect)
    }

    @Test("필터 목록은 고른 클립 모두에 들어가고, 나눈 조각도 같은 필터를 가지며, 실행 취소 한 번으로 돌아온다")
    func editorAppliesToSelection() throws {
        let editor = try makeEditor()
        let clips = try #require(editor.currentSequence.tracks.first?.clips)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project

        undoManager.beginUndoGrouping()
        editor.setFilters([VideoFilter(kind: .noir, intensity: 2), VideoFilter(kind: .blur, intensity: 0.3)], for: Set(clips.map(\.id)))
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == "필터")
        for clip in clips {
            #expect(editor.currentSequence.clip(id: clip.id)?.filters.map(\.kind) == [.noir, .blur])
            #expect(editor.currentSequence.clip(id: clip.id)?.filters.first?.intensity == 1)
        }

        undoManager.beginUndoGrouping()
        editor.splitClips([clips[0].id], at: seconds(4))
        undoManager.endUndoGrouping()
        let pieces = try #require(editor.currentSequence.tracks.first?.clips.filter { $0.assetID == clips[0].assetID })
        #expect(pieces.count == 2 && pieces.allSatisfy { $0.filters.map(\.kind) == [.noir, .blur] })

        undoManager.undo()
        undoManager.undo()
        #expect(editor.project == before)
    }

    @Test("모든 필터는 이미지 크기를 바꾸지 않고, 세기 0이면 원본 그대로다")
    func filtersKeepExtent() {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
        for kind in VideoFilterKind.allCases {
            let filtered = LayerCompositor.applying([VideoFilter(kind: kind, intensity: 0.8)], to: image)
            #expect(filtered.extent == image.extent, "\(kind)")
            #expect(LayerCompositor.applying([VideoFilter(kind: kind, intensity: 0)], to: image) == image)
        }
    }

    @Test("합성에서 세피아는 갈색으로, 흑백은 회색으로, 비네트는 가장자리를 어둡게, 블러는 경계를 섞는다")
    func compositionPixels() async throws {
        let blueURL = try TestMedia.makeImage(red: 40, green: 80, blue: 220)
        let whiteURL = try TestMedia.makeImage(red: 255, green: 255, blue: 255, width: 1600, height: 900)
        let splitURL = try TestMedia.makeSplitImage()
        let blue = MediaAsset(id: UUID(), name: "blue.png", sourceURL: blueURL, kind: .image, duration: MediaAsset.stillImageDuration)
        let white = MediaAsset(id: UUID(), name: "white.png", sourceURL: whiteURL, kind: .image, duration: MediaAsset.stillImageDuration)
        let split = MediaAsset(id: UUID(), name: "split.png", sourceURL: splitURL, kind: .image, duration: MediaAsset.stillImageDuration)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        // 0~1초 파랑+세피아, 1~2초 파랑+흑백, 2~3초 흰색+비네트, 3~4초 반반+블러.
        let plan: [(MediaAsset, VideoFilter)] = [
            (blue, VideoFilter(kind: .sepia, intensity: 1)),
            (blue, VideoFilter(kind: .noir, intensity: 1)),
            (white, VideoFilter(kind: .vignette, intensity: 1)),
            (split, VideoFilter(kind: .blur, intensity: 1)),
        ]
        for (index, (asset, filter)) in plan.enumerated() {
            var clip = try #require(asset.makeClip(at: seconds(Double(index))))
            clip.sourceRange = CMTimeRange(start: .zero, duration: seconds(1))
            clip.filters = [filter]
            sequence.place(clip, onTrack: trackID)
        }
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [blue, white, split], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sepia = try await TestMedia.centerColor(of: generator.image(at: seconds(0.5)).image)
        #expect(sepia.red > sepia.blue)
        let noir = try await TestMedia.centerColor(of: generator.image(at: seconds(1.5)).image)
        #expect(abs(noir.red - noir.blue) < 12 && abs(noir.green - noir.blue) < 12)
        let vignette = try await generator.image(at: seconds(2.5)).image
        let center = TestMedia.color(of: vignette, atX: 0.5, y: 0.5)
        let corner = TestMedia.color(of: vignette, atX: 0.03, y: 0.05)
        #expect(center.red > corner.red + 60)
        let blurred = try await TestMedia.centerColor(of: generator.image(at: seconds(3.5)).image)
        #expect(blurred.red > 60 && blurred.blue > 60)
    }

    @Test("필터(종류·세기·순서)는 저장했다가 그대로 불러온다")
    func persistence() throws {
        let editor = try makeEditor()
        let clip = try #require(editor.currentSequence.tracks.first?.clips.first)
        editor.setFilters([VideoFilter(kind: .vignette, intensity: 0.7), VideoFilter(kind: .pixellate, intensity: 0.2)], for: [clip.id])
        try editor.save()
        let loaded = try #require(try repository.project(id: editor.project.id))
        #expect(loaded == editor.project)
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
