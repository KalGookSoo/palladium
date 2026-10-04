import CoreMedia
import Foundation

/// 24·25·30·60fps로 모두 나누어떨어져, 흔한 프레임레이트의 프레임 경계를 반올림 없이 표현한다.
nonisolated let standardTimescale: CMTimeScale = 600

nonisolated struct Clip {
    let id: UUID
    let assetID: MediaAsset.ID
    var sourceRange: CMTimeRange
    var timelineStart: CMTime

    init?(id: UUID = UUID(), assetID: MediaAsset.ID, sourceRange: CMTimeRange, timelineStart: CMTime) {
        guard sourceRange.start.isNumeric, sourceRange.duration.isNumeric, sourceRange.duration > .zero, timelineStart.isNumeric, timelineStart >= .zero else { return nil }
        self.id = id
        self.assetID = assetID
        self.sourceRange = sourceRange
        self.timelineStart = timelineStart
    }
}

// MARK: - Queries

extension Clip {
    var timelineRange: CMTimeRange {
        CMTimeRange(start: timelineStart, duration: sourceRange.duration)
    }
}

nonisolated extension Clip: Identifiable {}
nonisolated extension Clip: Equatable {}
