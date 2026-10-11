import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 클립 회전(#66): 각도 규칙, 90도 버튼, 회전 손잡이, 합성(미리보기·내보내기 공통)에서 가운데 기준으로 돌기, 저장.
@MainActor
struct ClipRotationTests {
    @Test("각도는 같은 방향의 -180~180도로 맞추고, 90도 버튼은 90도씩 돌린다")
    func rotationRules() {
        #expect(ClipTransform.normalizedRotation(270) == -90)
        #expect(ClipTransform.normalizedRotation(-190) == 170)
        #expect(ClipTransform.normalizedRotation(180) == 180)
        #expect(ClipTransform.normalizedRotation(-180) == 180)
        #expect(ClipTransform.normalizedRotation(720) == 0)

        var transform = ClipTransform(rotation: 400)
        transform.clamp()
        #expect(transform.rotation == 40)

        let start = ClipTransform(rotation: 170)
        #expect(start.rotatedByQuarterTurn(clockwise: true).rotation == -100)
        #expect(start.rotatedByQuarterTurn(clockwise: false).rotation == 80)
    }

    @Test("회전 손잡이는 가운데에서 포인터 방향(위가 0도, 시계 방향)으로 돌리고, ⇧면 15도씩 맞춘다")
    func rotateTowardPointer() {
        let center = CGPoint(x: 100, y: 100)
        let transform = ClipTransform()
        #expect(abs(transform.rotated(toward: CGPoint(x: 100, y: 0), around: center, snapsToStep: false).rotation) < 1e-9)
        #expect(abs(transform.rotated(toward: CGPoint(x: 200, y: 100), around: center, snapsToStep: false).rotation - 90) < 1e-9)
        #expect(abs(transform.rotated(toward: CGPoint(x: 0, y: 100), around: center, snapsToStep: false).rotation + 90) < 1e-9)
        // 오른쪽 위 22도쯤 → ⇧면 15도.
        #expect(transform.rotated(toward: CGPoint(x: 140, y: 0), around: center, snapsToStep: true).rotation == 15)
    }

    @Test("180도 돌린 이미지는 가운데 기준으로 뒤집혀 왼쪽·오른쪽 색이 바뀌고, 90도는 화면에 맞춘 크기 그대로 돈다")
    func compositionRotatesAroundCenter() async throws {
        let url = try TestMedia.makeSplitImage()
        let image = MediaAsset(id: UUID(), name: "split.png", sourceURL: url, kind: .image, duration: MediaAsset.stillImageDuration)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        // 0~1초 그대로, 1~2초 180도, 2~3초 시계 방향 90도(반 크기로 줄여 화면 안에 둔다).
        for (index, transform) in [ClipTransform(), ClipTransform(rotation: 180), ClipTransform(scale: 0.5, rotation: 90)].enumerated() {
            var clip = try #require(image.makeClip(at: seconds(Double(index))))
            clip.sourceRange = CMTimeRange(start: .zero, duration: seconds(1))
            clip.transform = transform
            sequence.place(clip, onTrack: trackID)
        }
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [image], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let plain = try await generator.image(at: seconds(0.5)).image
        #expect(TestMedia.color(of: plain, atX: 0.25, y: 0.5).red > 200)
        #expect(TestMedia.color(of: plain, atX: 0.75, y: 0.5).blue > 200)

        let flipped = try await generator.image(at: seconds(1.5)).image
        #expect(TestMedia.color(of: flipped, atX: 0.25, y: 0.5).blue > 200)
        #expect(TestMedia.color(of: flipped, atX: 0.75, y: 0.5).red > 200)

        // 반 크기(화면 가운데 960×540)를 시계 방향으로 90도: 위쪽이 빨강(원래 왼쪽), 아래쪽이 파랑, 좌우 바깥은 검정.
        let quarter = try await generator.image(at: seconds(2.5)).image
        #expect(TestMedia.color(of: quarter, atX: 0.5, y: 0.3).red > 200)
        #expect(TestMedia.color(of: quarter, atX: 0.5, y: 0.7).blue > 200)
        let outside = TestMedia.color(of: quarter, atX: 0.3, y: 0.5)
        #expect(outside.red < 30 && outside.blue < 30)
    }

    @Test("회전 각도는 저장했다가 그대로 불러오고, 편집기 트랜스폼 커맨드가 범위로 맞춘다")
    func persistence() throws {
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
        let clip = try #require(editor.currentSequence.tracks.first?.clips.first)

        editor.setTransform(ClipTransform(rotation: 450), for: clip.id)
        #expect(editor.currentSequence.clip(id: clip.id)?.transform.rotation == 90)
        try editor.save()

        #expect(try repository.project(id: project.id)?.sequences[0].clip(id: clip.id)?.transform.rotation == 90)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
