import CoreMedia
import Foundation

/// 타임라인 클립 안에 그릴 필름스트립·파형의 배치 계산. 이미지 생성·오디오 읽기는 어댑터(`ClipContentProvider`)가 한다.
nonisolated enum ClipContentLayout {
    /// 파형을 미리 계산해 두는 해상도(초당 값 개수).
    static let peaksPerSecond = 100.0

    /// 클립 폭을 칸 폭으로 나눠 칸 개수를 정하고, 칸마다 가운데 시각의 원본 프레임을 쓴다.
    static func filmstripTimes(sourceRange: CMTimeRange, width: Double, tileWidth: Double) -> [CMTime] {
        guard width > 0, tileWidth > 0, sourceRange.duration > .zero else { return [] }
        let count = max(Int((width / tileWidth).rounded(.up)), 1)
        return (0 ..< count).map { index in
            let fraction = (Double(index) + 0.5) / Double(count)
            return sourceRange.start + CMTime(seconds: sourceRange.duration.seconds * fraction, preferredTimescale: standardTimescale)
        }
    }

    /// 원본 전체의 파형(초당 `peaksPerSecond`개)에서 클립 구간만 잘라 `bucketCount`개로 다시 묶는다. 묶음마다 가장 큰 값을 쓴다.
    static func clipPeaks(assetPeaks: [Float], sourceRange: CMTimeRange, bucketCount: Int) -> [Float] {
        let start = min(max(Int(sourceRange.start.seconds * peaksPerSecond), 0), assetPeaks.count)
        let end = min(max(Int(sourceRange.end.seconds * peaksPerSecond), start), assetPeaks.count)
        return peaks(of: Array(assetPeaks[start ..< end]), bucketCount: bucketCount)
    }

    /// 값을 `bucketCount`개 묶음으로 나눠 묶음마다 가장 큰 절댓값을 돌려준다. 값보다 묶음이 많으면 값 개수만큼만 돌려준다.
    static func peaks(of samples: [Float], bucketCount: Int) -> [Float] {
        guard !samples.isEmpty, bucketCount > 0 else { return [] }
        let count = min(bucketCount, samples.count)
        return (0 ..< count).map { bucket in
            let lower = bucket * samples.count / count
            let upper = max((bucket + 1) * samples.count / count, lower + 1)
            return samples[lower ..< upper].map(abs).max() ?? 0
        }
    }
}
