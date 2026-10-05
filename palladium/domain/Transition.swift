import CoreMedia
import Foundation

/// 앞 클립에서 이 클립으로 넘어가는 영상 전환(#8). 컷 지점을 가운데 두고 앞뒤로 절반씩 걸친다.
nonisolated struct ClipTransition {
    var kind: TransitionKind
    var duration: CMTime

    static let defaultDuration = CMTime(value: 1, timescale: 1)
    static let minimumDuration = CMTime(value: 1, timescale: 10)
}

nonisolated enum TransitionKind: String, CaseIterable {
    /// 앞 클립 위로 이 클립이 서서히 나타난다.
    case dissolve
    /// 이 클립이 왼쪽부터 밀고 들어온다.
    case wipe
}

nonisolated extension ClipTransition: Equatable {}

// MARK: - Track

nonisolated extension Track {
    /// 끝이 `clip` 시작과 맞닿은 바로 앞 클립. 틈이 있으면 전환할 앞 클립이 없다.
    func clip(before clip: Clip) -> Clip? {
        clips.first { $0.id != clip.id && $0.timelineRange.end == clip.timelineStart }
    }

    /// 앞 클립과의 전환·크로스페이드가 가질 수 있는 가장 긴 길이. 두 클립 중 짧은 쪽 길이를 넘지 않는다.
    /// 앞에 맞닿은 클립이 없으면 0이다.
    func maximumTransitionDuration(into clip: Clip) -> CMTime {
        guard let previous = self.clip(before: clip) else { return .zero }
        return CMTimeMinimum(previous.sourceRange.duration, clip.sourceRange.duration)
    }

    /// 실제로 그릴 전환. 앞 클립이 맞닿아 있지 않으면 `nil`이고, 트림·이동으로 클립이 짧아졌으면 그만큼 줄인다.
    func effectiveTransition(into clip: Clip) -> ClipTransition? {
        guard var transition = clip.transitionIn else { return nil }
        let maximum = maximumTransitionDuration(into: clip)
        guard maximum >= ClipTransition.minimumDuration else { return nil }
        transition.duration = CMTimeMinimum(transition.duration, maximum)
        return transition
    }

    /// 실제로 적용할 오디오 크로스페이드 길이. 규칙은 영상 전환과 같다.
    func effectiveAudioCrossfade(into clip: Clip) -> CMTime? {
        guard let duration = clip.audioCrossfadeIn else { return nil }
        let maximum = maximumTransitionDuration(into: clip)
        guard maximum >= ClipTransition.minimumDuration else { return nil }
        return CMTimeMinimum(duration, maximum)
    }
}

// MARK: - EditSequence

nonisolated extension EditSequence {
    /// `nil`이면 전환을 없앤다. 길이는 최소 길이와 가능한 최대 길이 사이로 맞춘다. 앞에 맞닿은 클립이 없으면 둘 수 없어 없앤다.
    mutating func setTransition(_ transition: ClipTransition?, forClip clipID: Clip.ID) {
        updateTransitionClip(clipID) { clip, maximum in
            clip.transitionIn = transition.flatMap { transition in
                Self.clampedTransitionDuration(transition.duration, maximum: maximum).map { ClipTransition(kind: transition.kind, duration: $0) }
            }
        }
    }

    /// `nil`이면 크로스페이드를 없앤다. 규칙은 `setTransition`과 같다.
    mutating func setAudioCrossfade(_ duration: CMTime?, forClip clipID: Clip.ID) {
        updateTransitionClip(clipID) { clip, maximum in
            clip.audioCrossfadeIn = duration.flatMap { Self.clampedTransitionDuration($0, maximum: maximum) }
        }
    }

    private mutating func updateTransitionClip(_ clipID: Clip.ID, _ change: (inout Clip, CMTime) -> Void) {
        for trackIndex in tracks.indices {
            guard let clipIndex = tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else { continue }
            let maximum = tracks[trackIndex].maximumTransitionDuration(into: tracks[trackIndex].clips[clipIndex])
            change(&tracks[trackIndex].clips[clipIndex], maximum)
            return
        }
    }

    /// 가능한 최대 길이가 최소 길이보다 짧으면(앞에 맞닿은 클립이 없으면) `nil`.
    private static func clampedTransitionDuration(_ duration: CMTime, maximum: CMTime) -> CMTime? {
        guard maximum >= ClipTransition.minimumDuration else { return nil }
        return CMTimeMinimum(CMTimeMaximum(duration, ClipTransition.minimumDuration), maximum)
    }
}
