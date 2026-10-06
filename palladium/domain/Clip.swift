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
    /// 바로 앞 클립에서 넘어오는 영상 전환(#8). 앞 클립과 맞닿아 있을 때만 그린다.
    var transitionIn: ClipTransition?
    /// 바로 앞 클립과의 오디오 크로스페이드 길이(#8). 영상 전환과 따로 정한다.
    var audioCrossfadeIn: CMTime?
    /// 재생 속도(#58). 2면 두 배 빠르게 재생해 타임라인 길이가 절반이다. `speedOptions` 중 하나다.
    var speed = 1.0
    /// 타임라인에서 쓰임새를 구분하는 별칭(#78). `nil`이면 원본 이름을 보여준다.
    var name: String?
    /// 클립 색상 레이블(#78). 원본과 같은 7색을 쓴다.
    var colorLabel: ColorLabel?

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
    /// 고를 수 있는 재생 속도. 타임라인 길이를 정확히 나누어떨어지게 계산할 수 있는 값만 둔다.
    static let speedOptions = [0.25, 0.5, 1.0, 2.0, 4.0]
    /// 속도를 바꾼 클립의 시간 계산 단위(1/60000초). 600 단위 시각을 속도 배율로 나눠도 반올림이 생기지 않는다.
    private static let speedTimescale: CMTimeScale = 60000

    var timelineRange: CMTimeRange {
        CMTimeRange(start: timelineStart, duration: timelineDuration)
    }

    /// 타임라인에서 차지하는 길이(원본 구간 길이 ÷ 속도).
    var timelineDuration: CMTime {
        timelineTime(forSource: sourceRange.duration)
    }

    /// 원본 시간 `duration`이 타임라인에서 차지하는 시간.
    func timelineTime(forSource duration: CMTime) -> CMTime {
        speed == 1 ? duration : Self.scaled(duration, by: 1 / speed)
    }

    /// 타임라인 시간 `duration`에 해당하는 원본 시간.
    func sourceTime(forTimeline duration: CMTime) -> CMTime {
        speed == 1 ? duration : Self.scaled(duration, by: speed)
    }

    private static func scaled(_ time: CMTime, by factor: Double) -> CMTime {
        let fine = CMTimeConvertScale(time, timescale: speedTimescale, method: .roundHalfAwayFromZero)
        return CMTime(value: CMTimeValue((Double(fine.value) * factor).rounded()), timescale: speedTimescale)
    }

    /// 타임라인·인스펙터에 보일 이름. 별칭이 없으면 원본 이름이다.
    func displayName(assetName: String) -> String {
        name ?? assetName
    }
}

// MARK: - Commands

nonisolated extension Clip {
    /// 별칭을 바꾼다. 앞뒤 공백을 빼고, 비어 있으면 별칭을 떼 원본 이름을 보여준다.
    mutating func rename(to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? nil : trimmedName
    }
}

nonisolated extension Clip: Identifiable {}
nonisolated extension Clip: Equatable {}
