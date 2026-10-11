import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import SwiftData
import Testing

/// 오디오 이펙트(#74): 신호 처리(게인·저음 컷·EQ·게이트·잔향), 내보내기에 처리 탭이 들어가는지, 편집기·저장.
struct AudioEffectsTests {
    private let sampleRate = 48000.0

    /// 사인파를 처리기에 통과시킨 뒤 뒤쪽 절반의 최대 진폭(필터가 자리 잡은 뒤).
    private func peak(frequency: Double, amplitude: Float = 0.5, seconds: Double = 0.5, effects: AudioEffects) -> Float {
        let processor = AudioEffectProcessor(effects: effects, sampleRate: sampleRate, channelCount: 1)
        let count = Int(sampleRate * seconds)
        var maximum: Float = 0
        for index in 0 ..< count {
            let input = amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate))
            let output = processor.process(input, channel: 0)
            if index > count / 2 {
                maximum = max(maximum, abs(output))
            }
        }
        return maximum
    }

    @Test("게인은 dB만큼 키우고 줄이며, 기본값은 소리를 바꾸지 않는다")
    func gain() {
        #expect(abs(peak(frequency: 440, effects: AudioEffects()) - 0.5) < 0.01)
        #expect(abs(peak(frequency: 440, effects: AudioEffects(gain: 6)) - 0.5 * 1.995) < 0.02)
        #expect(abs(peak(frequency: 440, effects: AudioEffects(gain: -6)) - 0.5 * 0.501) < 0.01)
    }

    @Test("저음 웅웅거림 깎기는 30Hz를 크게 줄이고 1kHz는 거의 그대로 둔다")
    func rumbleCut() {
        let effects = AudioEffects(cutsLowRumble: true)
        #expect(peak(frequency: 30, effects: effects) < 0.5 * 0.2)
        #expect(peak(frequency: 1000, effects: effects) > 0.5 * 0.95)
    }

    @Test("이퀄라이저: 저음 +12dB는 100Hz를, 고음 +12dB는 10kHz를 키우고, 중음 -12dB는 1kHz를 줄인다")
    func equalizer() {
        #expect(peak(frequency: 100, effects: AudioEffects(lowGain: 12)) > 0.5 * 3)
        #expect(peak(frequency: 10000, effects: AudioEffects(highGain: 12)) > 0.5 * 3)
        #expect(peak(frequency: 1000, effects: AudioEffects(midGain: -12)) < 0.5 * 0.35)
        // 저음을 키워도 고음은 거의 그대로다(8kHz는 샘플 최대값이 진폭보다 작아 이펙트 없는 값과 비교한다).
        let plainHigh = peak(frequency: 8000, effects: AudioEffects())
        #expect(abs(peak(frequency: 8000, effects: AudioEffects(lowGain: 12)) - plainHigh) < 0.01)
    }

    @Test("노이즈 게이트는 작은 잡음은 줄이고 말소리처럼 큰 소리는 그대로 둔다")
    func noiseGate() {
        let effects = AudioEffects(noiseGate: 0.5)
        #expect(peak(frequency: 300, amplitude: 0.001, effects: effects) < 0.001 * 0.2)
        #expect(peak(frequency: 300, amplitude: 0.5, effects: effects) > 0.5 * 0.95)
    }

    @Test("잔향은 소리가 끝난 뒤에도 울림을 남긴다")
    func reverbTail() {
        let processor = AudioEffectProcessor(effects: AudioEffects(reverb: 1), sampleRate: sampleRate, channelCount: 1)
        var tail: Float = 0
        for index in 0 ..< Int(sampleRate * 0.3) {
            let output = processor.process(index == 0 ? 1 : 0, channel: 0)
            if index > Int(sampleRate * 0.05) {
                tail = max(tail, abs(output))
            }
        }
        #expect(tail > 0.01)
        let dry = AudioEffectProcessor(effects: AudioEffects(), sampleRate: sampleRate, channelCount: 1)
        #expect(dry.process(0, channel: 0) == 0)
    }

    @Test("내보내기는 소리 이펙트(게인 -12dB)를 처리 탭으로 넣어 결과물 소리가 작아진다")
    func exportAppliesTap() async throws {
        let toneURL = try TestMedia.makeTone(seconds: 1)
        let tone = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: toneURL, kind: .audio, duration: CMTime(value: 1, timescale: 1))
        func exportedPeak(effects: AudioEffects) async throws -> Float {
            var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
            let trackID = sequence.addTrack(kind: .audio)
            var clip = try #require(tone.makeClip(at: .zero))
            clip.audioEffects = effects
            sequence.place(clip, onTrack: trackID)
            let composition = try #require(await SequenceComposer.makeComposition(sequence: sequence, assets: [tone], aspectRatio: .landscape16x9, resolveURL: \.sourceURL))
            let output = TestMedia.temporaryURL(extension: "mp4")
            try await SequenceExporter.export(composition, to: output) { _ in }
            return try await Self.peak(of: output)
        }
        let plain = try await exportedPeak(effects: AudioEffects())
        let quieter = try await exportedPeak(effects: AudioEffects(gain: -12))
        #expect(plain > 0.3)
        #expect(quieter < plain * 0.4)
    }

    @MainActor
    @Test("소리 이펙트는 범위로 맞추고, 나눈 조각도 같은 이펙트를 가지며, 저장했다가 그대로 불러온다")
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
        let music = try #require(editor.currentSequence.tracks.first { $0.kind == .audio }?.clips.first)

        editor.setAudioEffects(AudioEffects(lowGain: 30, cutsLowRumble: true, reverb: 0.3, noiseGate: 2, gain: -40), for: music.id)
        let saved = try #require(editor.currentSequence.clip(id: music.id)?.audioEffects)
        #expect(saved.lowGain == 12 && saved.noiseGate == 1 && saved.gain == -12 && saved.cutsLowRumble)
        #expect(editor.currentSequence.clip(id: music.id)?.hasEffect == true)

        editor.splitClips([music.id], at: CMTime(value: 5, timescale: 1))
        #expect(editor.currentSequence.tracks.first { $0.kind == .audio }?.clips.allSatisfy { $0.audioEffects == saved } == true)

        try editor.save()
        #expect(try repository.project(id: project.id) == editor.project)
    }

    /// 파일 소리의 가운데 0.6초 동안의 최대 진폭.
    private static func peak(of url: URL) async throws -> Float {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(value: 2, timescale: 10), duration: CMTime(value: 6, timescale: 10))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()
        var maximum: Float = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &values)
            maximum = max(maximum, values.map(abs).max() ?? 0)
        }
        return maximum
    }
}
