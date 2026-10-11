import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 크로마키(#70): 투명도·번짐 제거 규칙, 위 트랙에서 배경을 빼 아래 트랙과 합성, 편집기·저장.
@MainActor
struct ChromaKeyTests {
    @Test("키 색과 같은 색은 투명, 먼 색은 불투명이고, 그림자 진 초록도 빠지며, 부드러움 폭에서 서서히 바뀐다")
    func alphaRules() {
        let key = ChromaKey()
        #expect(key.alpha(red: 0, green: 1, blue: 0) == 0)
        #expect(key.alpha(red: 0.1, green: 0.7, blue: 0.1) == 0)
        #expect(key.alpha(red: 1, green: 0, blue: 0) == 1)
        #expect(key.alpha(red: 0.9, green: 0.7, blue: 0.6) == 1)
        #expect(key.alpha(red: 1, green: 1, blue: 1) == 1)

        var soft = ChromaKey(tolerance: 0.2, softness: 0.4)
        let middle = soft.alpha(red: 0.4, green: 0.8, blue: 0.4)
        #expect(middle > 0 && middle < 1)
        soft.softness = 0
        #expect([0, 1].contains(soft.alpha(red: 0.4, green: 0.8, blue: 0.4)))

        let blueKey = ChromaKey(keyColor: ChromaKey.blue)
        #expect(blueKey.alpha(red: 0, green: 0, blue: 1) == 0)
        #expect(blueKey.alpha(red: 0, green: 1, blue: 0) == 1)
    }

    @Test("번짐 제거는 초록 기운을 덜어 내고 밝기는 지키며, 초록 기운이 없는 색은 그대로 둔다")
    func spillRules() {
        let key = ChromaKey(spillSuppression: 1)
        let greenish = key.spillSuppressed(red: 0.6, green: 0.8, blue: 0.6)
        #expect(greenish.green < 0.8)
        let luma = { (color: (red: Double, green: Double, blue: Double)) in 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue }
        #expect(abs(luma(greenish) - luma((0.6, 0.8, 0.6))) < 0.02)
        let red = key.spillSuppressed(red: 1, green: 0.2, blue: 0.2)
        #expect(red == (1, 0.2, 0.2))
        #expect(ChromaKey(spillSuppression: 0).spillSuppressed(red: 0.6, green: 0.8, blue: 0.6) == (0.6, 0.8, 0.6))
    }

    @Test("위 트랙 그린스크린에 크로마키를 켜면 초록 자리에 아래 트랙이 비치고, 끄면 초록이 그대로 보인다")
    func composition() async throws {
        let greenURL = try TestMedia.makeImage(red: 0, green: 230, blue: 0, width: 1600, height: 900)
        let blueURL = try TestMedia.makeImage(red: 0, green: 0, blue: 255, width: 1600, height: 900)
        let green = MediaAsset(id: UUID(), name: "green.png", sourceURL: greenURL, kind: .image, duration: MediaAsset.stillImageDuration)
        let blue = MediaAsset(id: UUID(), name: "blue.png", sourceURL: blueURL, kind: .image, duration: MediaAsset.stillImageDuration)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let main = sequence.addTrack(kind: .video)
        let overlay = sequence.addTrack(kind: .video)
        var background = try #require(blue.makeClip(at: .zero))
        background.sourceRange = CMTimeRange(start: .zero, duration: seconds(2))
        sequence.place(background, onTrack: main)
        // 0~1초 크로마키 켬, 1~2초 끔.
        var keyed = try #require(green.makeClip(at: .zero))
        keyed.sourceRange = CMTimeRange(start: .zero, duration: seconds(1))
        keyed.chromaKey = ChromaKey()
        sequence.place(keyed, onTrack: overlay)
        var plain = try #require(green.makeClip(at: seconds(1)))
        plain.sourceRange = CMTimeRange(start: .zero, duration: seconds(1))
        sequence.place(plain, onTrack: overlay)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [green, blue], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let keyedFrame = try await TestMedia.centerColor(of: generator.image(at: seconds(0.5)).image)
        #expect(keyedFrame.blue > 200 && keyedFrame.green < 60)
        let plainFrame = try await TestMedia.centerColor(of: generator.image(at: seconds(1.5)).image)
        #expect(plainFrame.green > 180 && plainFrame.blue < 60)
    }

    @Test("크로마키는 고른 클립 모두에 켜고 끄며, 범위로 맞추고, 저장했다가 그대로 불러온다")
    func editorAndPersistence() throws {
        let container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.autosaveEnabled = false
        let repository = SwiftDataProjectRepository(modelContext: container.mainContext)
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        let editor = ProjectEditor(project: project, repository: repository)
        let clips = try #require(editor.currentSequence.tracks.first?.clips)

        editor.setChromaKey(ChromaKey(tolerance: 5, softness: -1), for: Set(clips.map(\.id)))
        for clip in clips {
            let key = try #require(editor.currentSequence.clip(id: clip.id)?.chromaKey)
            #expect(key.tolerance == 1 && key.softness == 0)
            #expect(editor.currentSequence.clip(id: clip.id)?.hasEffect == true)
        }
        try editor.save()
        #expect(try repository.project(id: project.id) == editor.project)

        editor.setChromaKey(nil, for: [clips[0].id])
        #expect(editor.currentSequence.clip(id: clips[0].id)?.chromaKey == nil)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
