import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import Testing

struct ClipContentLayoutTests {
    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    @Test("필름스트립 칸은 클립 폭을 칸 폭으로 올림해 나누고, 칸마다 가운데 시각을 쓴다")
    func filmstripTimes() {
        let range = CMTimeRange(start: seconds(2), duration: seconds(4))
        let times = ClipContentLayout.filmstripTimes(sourceRange: range, width: 150, tileWidth: 64)
        let expected: [Double] = [2 + 4.0 / 6, 4, 6 - 4.0 / 6]
        #expect(zip(times.map(\.seconds), expected).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(times.count == 3)
        #expect(ClipContentLayout.filmstripTimes(sourceRange: range, width: 0, tileWidth: 64).isEmpty)
    }

    @Test("파형은 묶음마다 가장 큰 절댓값을 쓰고, 클립 구간만 잘라 묶는다")
    func peaks() {
        #expect(ClipContentLayout.peaks(of: [0.1, -0.5, 0.2, 0.3], bucketCount: 2) == [0.5, 0.3])
        #expect(ClipContentLayout.peaks(of: [0.1, 0.2], bucketCount: 5) == [0.1, 0.2])

        let assetPeaks = (0 ..< 300).map { Float($0) / 300 }
        let clipPeaks = ClipContentLayout.clipPeaks(assetPeaks: assetPeaks, sourceRange: CMTimeRange(start: seconds(1), duration: seconds(1)), bucketCount: 10)
        #expect(clipPeaks.count == 10)
        #expect(clipPeaks.last == assetPeaks[199])
    }
}

@MainActor
struct ClipContentProviderTests {
    @Test("오디오 파일의 파형은 초당 100개이고 소리가 있는 구간은 0보다 크다")
    func readsPeaks() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        for index in 0 ..< 44100 {
            buffer.floatChannelData?[0][index] = 0.5 * sin(Float(index) * 2 * .pi * 440 / 44100)
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        let asset = MediaAsset(id: UUID(), name: "tone.wav", sourceURL: url, kind: .audio, duration: CMTime(value: 1, timescale: 1))

        let peaks = await ClipContentProvider().peaks(for: asset)

        #expect(abs(peaks.count - 100) <= 1)
        #expect(peaks.allSatisfy { $0 > 0.3 && $0 <= 1 })
    }

    @Test("파일이 없는 원본은 파형도 프레임도 없다")
    func missingFiles() async {
        let provider = ClipContentProvider()
        #expect(await provider.peaks(for: SampleData.backgroundMusic).isEmpty)
        #expect(await provider.frames(for: SampleData.bRollVideo, at: [.zero]) == [nil])
    }
}
