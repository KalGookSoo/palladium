import CoreMedia
import Foundation

/// 24·25·30·60fps로 모두 나누어떨어져, 흔한 프레임레이트의 프레임 경계를 반올림 없이 표현한다.
nonisolated let standardTimescale: CMTimeScale = 600

nonisolated struct Clip {
    let id: UUID
    let assetID: MediaAsset.ID
    var sourceRange: CMTimeRange
    var timelineStart: CMTime
    /// 화면에 그릴 위치·크기·불투명도(오버레이용). 기본은 화면에 꽉 맞춘 그대로다.
    var transform = ClipTransform()
    /// 이 클립 소리의 크기(0~1). 영상 클립은 영상에 담긴 소리다(#44).
    var volume = 1.0
    var isMuted = false

    init?(id: UUID = UUID(), assetID: MediaAsset.ID, sourceRange: CMTimeRange, timelineStart: CMTime) {
        guard sourceRange.start.isNumeric, sourceRange.duration.isNumeric, sourceRange.duration > .zero, timelineStart.isNumeric, timelineStart >= .zero else { return nil }
        self.id = id
        self.assetID = assetID
        self.sourceRange = sourceRange
        self.timelineStart = timelineStart
    }
}

// MARK: - Queries

nonisolated extension Clip {
    var timelineRange: CMTimeRange {
        CMTimeRange(start: timelineStart, duration: sourceRange.duration)
    }
}

nonisolated extension Clip: Identifiable {}
nonisolated extension Clip: Equatable {}
