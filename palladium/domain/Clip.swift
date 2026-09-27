import CoreMedia
import Foundation

/// 타임라인 위에 놓인 클립 하나. 원본 미디어의 어느 구간을 타임라인의 어느 위치에 놓을지 나타낸다.
nonisolated struct Clip {
    /// 클립을 구분하는 고유 식별자.
    let id: UUID
    /// 이 클립이 참조하는 원본 미디어의 식별자.
    let assetID: MediaAsset.ID
    /// 원본 미디어 안에서 사용하는 구간(in/out 트림 지점).
    var sourceRange: CMTimeRange
    /// 타임라인에서 이 클립이 시작하는 위치.
    var timelineStart: CMTime

    /// 클립을 만든다. 구간이 유효하지 않거나 길이가 0 이하이면, 또는 타임라인 시작 위치가 음수이면 만들지 않고 `nil`을 반환한다.
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
    /// 타임라인에서 이 클립이 차지하는 구간.
    var timelineRange: CMTimeRange {
        CMTimeRange(start: timelineStart, duration: sourceRange.duration)
    }
}

extension Clip: Identifiable {}
extension Clip: Equatable {}
