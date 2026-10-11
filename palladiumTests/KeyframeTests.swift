import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 키프레임 애니메이션(#67): 보간, 원본 시각 기준(트림·속도·분할), 편집기 커맨드, 합성(그림·소리), 저장.
@MainActor
struct KeyframeTests {
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

    // MARK: - 보간

    @Test("키프레임 사이는 앞 키프레임의 보간(선형·감속)으로 잇고, 처음 앞·마지막 뒤는 그 값에 머문다")
    func interpolation() {
        var keys: [Keyframe<Double>] = []
        keys.setKeyframe(0, at: seconds(1))
        keys.setKeyframe(1, at: seconds(3))
        let lerp = { (from: Double, to: Double, progress: Double) in from + (to - from) * progress }
        #expect(keys.value(at: .zero, interpolate: lerp) == 0)
        #expect(keys.value(at: seconds(2), interpolate: lerp) == 0.5)
        #expect(keys.value(at: seconds(5), interpolate: lerp) == 1)
        keys[0].interpolation = .easeOut
        #expect(keys.value(at: seconds(2), interpolate: lerp) == 0.75)
        // 같은 시각(반 프레임 안)에 두면 값만 바뀐다.
        keys.setKeyframe(0.2, at: CMTime(value: 601, timescale: 600))
        #expect(keys.count == 2 && keys[0].value == 0.2 && keys[0].interpolation == .easeOut)
        #expect([Keyframe<Double>]().value(at: .zero, interpolate: lerp) == nil)
    }

    @Test("키프레임은 원본 시각에 붙어 있어 클립 앞을 트림하거나 속도를 바꿔도 같은 장면에서 같은 값이다")
    func sourceTimeBased() throws {
        var clip = try #require(Clip(assetID: UUID(), sourceRange: range(0, 10), timelineStart: seconds(5)))
        clip.animation.transform = [
            Keyframe(time: seconds(2), value: ClipTransform(opacity: 0)),
            Keyframe(time: seconds(4), value: ClipTransform(opacity: 1)),
        ]
        // 원본 3초는 타임라인 8초.
        #expect(abs(clip.transform(atTimeline: seconds(8)).opacity - 0.5) < 1e-9)
        #expect(clip.keyframeTimes(of: .transform) == [seconds(7), seconds(9)])

        // 앞을 1초 트림하면 원본 3초는 타임라인 7초.
        clip.sourceRange = range(1, 10)
        #expect(abs(clip.transform(atTimeline: seconds(7)).opacity - 0.5) < 1e-9)

        // 2배 속도면 원본 3초는 타임라인 5 + (3-1)/2 = 6초.
        clip.speed = 2
        #expect(abs(clip.transform(atTimeline: seconds(6)).opacity - 0.5) < 1e-9)
    }

    @Test("◆는 지금 값으로 키프레임을 두거나 지우고, 키프레임이 있으면 값을 바꿀 때 재생 헤드에 키프레임이 생긴다. 모두 지우면 그때 값이 고정 값이 된다")
    func editorCommands() throws {
        let editor = try makeEditor()
        let clip = try #require(editor.currentSequence.tracks.first?.clips.first)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        editor.undoManager = undoManager
        let before = editor.project
        /// 묶음 없이 편집을 남기면 예외가 나 스위트가 끝나지 않으므로 편집마다 묶는다.
        func grouped(_ edit: () -> Void) {
            undoManager.beginUndoGrouping()
            edit()
            undoManager.endUndoGrouping()
        }

        // 키프레임이 없으면 고정 값을 바꾼다.
        grouped { editor.setTransform(ClipTransform(scale: 0.5), for: clip.id, at: seconds(1)) }
        #expect(editor.currentSequence.clip(id: clip.id)?.transform.scale == 0.5)
        #expect(editor.currentSequence.clip(id: clip.id)?.animation.isEmpty == true)

        grouped { editor.toggleKeyframe(.transform, for: clip.id, at: seconds(1)) }
        #expect(undoManager.undoActionName == "키프레임")
        grouped { editor.setTransform(ClipTransform(scale: 1.5), for: clip.id, at: seconds(5)) }
        let animated = try #require(editor.currentSequence.clip(id: clip.id))
        #expect(animated.animation.transform.map(\.value.scale) == [0.5, 1.5])
        #expect(abs(animated.transform(atTimeline: seconds(3)).scale - 1.0) < 1e-9)

        grouped { editor.setKeyframeInterpolation(.easeOut, for: .transform, clipID: clip.id, at: seconds(1)) }
        #expect(editor.currentSequence.clip(id: clip.id)?.keyframeInterpolation(.transform, atTimeline: seconds(1)) == .easeOut)

        // 지우기: 키프레임 하나를 지우면 하나가 남는다.
        grouped { editor.toggleKeyframe(.transform, for: clip.id, at: seconds(5)) }
        #expect(editor.currentSequence.clip(id: clip.id)?.animation.transform.count == 1)

        grouped { editor.setTransform(ClipTransform(scale: 2), for: clip.id, at: seconds(6)) }
        grouped { editor.clearKeyframes(.transform, for: clip.id, at: seconds(6)) }
        let cleared = try #require(editor.currentSequence.clip(id: clip.id))
        #expect(cleared.animation.transform.isEmpty && cleared.transform.scale == 2)

        // 음소거만 바꾸면 음량 키프레임이 생기지 않는다.
        grouped { editor.toggleKeyframe(.volume, for: clip.id, at: seconds(1)) }
        grouped { editor.setClipAudio(volume: nil, isMuted: true, for: clip.id, at: seconds(4)) }
        #expect(editor.currentSequence.clip(id: clip.id)?.animation.volume.count == 1)
        #expect(editor.currentSequence.clip(id: clip.id)?.isMuted == true)

        while undoManager.canUndo {
            undoManager.undo()
        }
        #expect(editor.project == before)
    }

    @Test("나눈 두 조각은 같은 키프레임을 갖고, 각 조각은 자기 구간에서 원래와 같은 값을 보인다")
    func splitKeepsAnimation() throws {
        var clip = try #require(Clip(assetID: UUID(), sourceRange: range(0, 4), timelineStart: .zero))
        clip.animation.volume = [Keyframe(time: .zero, value: 0), Keyframe(time: seconds(4), value: 1)]
        var track = Track(id: UUID(), kind: .audio, clips: [clip])
        track.split(at: seconds(2), clipIDs: nil)
        #expect(track.clips.count == 2)
        #expect(track.clips.allSatisfy { $0.animation == clip.animation })
        #expect(abs(track.clips[1].volume(atTimeline: seconds(3)) - 0.75) < 1e-9)
        #expect(track.clips[0].keyframeTimes(of: .volume) == [.zero])
        #expect(track.clips[1].keyframeTimes(of: .volume) == [seconds(4)])
    }

    // MARK: - 합성

    @Test("불투명도 키프레임으로 서서히 나타나고(페이드 인), 미리보기·내보내기 합성이 프레임마다 그 값을 그린다")
    func compositionFadesIn() async throws {
        let url = try TestMedia.makeImage(red: 255, green: 255, blue: 255)
        let image = MediaAsset(id: UUID(), name: "white.png", sourceURL: url, kind: .image, duration: MediaAsset.stillImageDuration)
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        var clip = try #require(image.makeClip(at: .zero))
        clip.sourceRange = range(0, 2)
        clip.animation.transform = [
            Keyframe(time: .zero, value: ClipTransform(opacity: 0)),
            Keyframe(time: seconds(2), value: ClipTransform(opacity: 1)),
        ]
        sequence.place(clip, onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [image], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let generator = AVAssetImageGenerator(asset: composition.asset)
        generator.videoComposition = composition.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let early = try await TestMedia.centerColor(of: generator.image(at: seconds(0.2)).image)
        let middle = try await TestMedia.centerColor(of: generator.image(at: seconds(1)).image)
        let late = try await TestMedia.centerColor(of: generator.image(at: seconds(1.9)).image)
        // Core Image는 선형 색공간에서 섞어 불투명도 0.1·0.5·0.95가 화면 값 약 89·188·250이 된다.
        #expect(early.red < 120)
        #expect(early.red < middle.red && middle.red < late.red)
        #expect(middle.red > 150 && middle.red < 220)
        #expect(late.red > 235)
    }

    @Test("음량 키프레임은 오디오 믹스 음량 변화로 들어가 시각마다 그 음량이 된다")
    func compositionFollowsVolumeKeyframes() async throws {
        let url = try TestMedia.makeTone(seconds: 2)
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: url, kind: .audio, duration: seconds(2))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .audio)
        var clip = try #require(tone.makeClip(at: .zero))
        clip.animation.volume = [Keyframe(time: .zero, value: 1), Keyframe(time: seconds(2), value: 0)]
        sequence.place(clip, onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(
            sequence: sequence, assets: [tone], aspectRatio: .landscape16x9, resolveURL: \.sourceURL
        ))
        let parameters = try #require(composition.audioMix?.inputParameters.first)
        func volume(at time: CMTime) -> Float? {
            var start: Float = 0
            var end: Float = 0
            var timeRange = CMTimeRange()
            guard parameters.getVolumeRamp(for: time, startVolume: &start, endVolume: &end, timeRange: &timeRange) else { return nil }
            let fraction = Float((time - timeRange.start).seconds / timeRange.duration.seconds)
            return start + (end - start) * fraction
        }
        #expect(try abs(#require(volume(at: seconds(0.5))) - 0.75) < 0.02)
        #expect(try abs(#require(volume(at: seconds(1.5))) - 0.25) < 0.02)
    }

    // MARK: - 저장

    @Test("키프레임(시각·값·보간)은 저장했다가 그대로 불러온다")
    func persistence() throws {
        let editor = try makeEditor()
        let clip = try #require(editor.currentSequence.tracks.first?.clips.first)
        editor.toggleKeyframe(.transform, for: clip.id, at: seconds(1))
        editor.setTransform(ClipTransform(centerX: 0.2, scale: 0.4, opacity: 0.5, rotation: 30), for: clip.id, at: seconds(3))
        editor.setKeyframeInterpolation(.easeOut, for: .transform, clipID: clip.id, at: seconds(1))
        editor.toggleKeyframe(.volume, for: clip.id, at: seconds(2))
        try editor.save()

        let loaded = try #require(try repository.project(id: editor.project.id))
        #expect(loaded == editor.project)
        #expect(loaded.sequences[0].clip(id: clip.id)?.animation.transform.count == 2)
    }

    // MARK: - Helpers

    private func makeEditor() throws -> ProjectEditor {
        let created = try repository.createProject(named: "샘플")
        let sample = SampleData.project
        let project = try #require(Project(id: created.id, name: created.name, assets: sample.assets, folders: sample.folders, sequences: sample.sequences))
        try repository.save(project)
        return ProjectEditor(project: project, repository: repository)
    }

    private func range(_ start: Double, _ end: Double) -> CMTimeRange {
        CMTimeRange(start: seconds(start), end: seconds(end))
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
