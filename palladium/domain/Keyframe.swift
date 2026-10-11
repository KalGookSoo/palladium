import CoreMedia
import Foundation

/// 키프레임 사이를 잇는 방식(#67). 앞 키프레임의 보간이 그 뒤 구간에 쓰인다.
nonisolated enum KeyframeInterpolation: String, CaseIterable {
    /// 일정한 빠르기로.
    case linear
    /// 처음에 빠르고 끝에서 천천히 멈춘다(감속).
    case easeOut

    /// 구간 진행(0~1)을 보간한 진행.
    func progress(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        switch self {
        case .linear: return clamped
        case .easeOut: return 1 - (1 - clamped) * (1 - clamped)
        }
    }
}

/// 원본 시각(`time`)에 둔 값 하나(#67). 시각을 원본 기준으로 두어 트림·분할·속도 변경·슬립에도 키프레임이 그 장면에 붙어 있다.
nonisolated struct Keyframe<Value: Equatable>: Equatable {
    var time: CMTime
    var value: Value
    var interpolation = KeyframeInterpolation.linear
}

/// 클립의 시간에 따른 변화(#67). 트랜스폼(위치·크기·회전·불투명도를 한 묶음으로)과 음량을 따로 둔다.
/// 키프레임이 없는 속성은 클립의 고정 값(`Clip.transform`·`Clip.volume`)을 쓴다.
nonisolated struct ClipAnimation: Equatable {
    var transform: [Keyframe<ClipTransform>] = []
    var volume: [Keyframe<Double>] = []

    var isEmpty: Bool {
        transform.isEmpty && volume.isEmpty
    }
}

/// 키프레임을 줄 속성.
nonisolated enum AnimatedProperty: String, CaseIterable {
    case transform
    case volume
}

// MARK: - Keyframe list

nonisolated extension Array {
    /// 같은 시각으로 볼 거리(60fps 반 프레임).
    static var keyframeTolerance: CMTime {
        CMTime(value: 1, timescale: 120)
    }

    /// `time`에 있는(반 프레임 안) 키프레임의 위치.
    func keyframeIndex<Value>(at time: CMTime) -> Int? where Element == Keyframe<Value> {
        firstIndex { abs(($0.time - time).seconds) <= Self.keyframeTolerance.seconds }
    }

    /// `time`의 값. 처음 키프레임 앞은 처음 값, 마지막 뒤는 마지막 값이고, 사이는 앞 키프레임의 보간으로 잇는다. 키프레임이 없으면 `nil`.
    func value<Value>(at time: CMTime, interpolate: (Value, Value, Double) -> Value) -> Value? where Element == Keyframe<Value> {
        guard let first, let last else { return nil }
        if time <= first.time {
            return first.value
        }
        if time >= last.time {
            return last.value
        }
        guard let nextIndex = firstIndex(where: { $0.time > time }), nextIndex > 0 else { return last.value }
        let previous = self[nextIndex - 1]
        let next = self[nextIndex]
        let span = (next.time - previous.time).seconds
        let fraction = span > 0 ? (time - previous.time).seconds / span : 1
        return interpolate(previous.value, next.value, previous.interpolation.progress(fraction))
    }

    /// `time`에 값을 둔다. 그 시각에 키프레임이 있으면 값만 바꾸고(보간은 그대로), 없으면 시각 순서대로 넣는다.
    mutating func setKeyframe<Value>(_ value: Value, at time: CMTime) where Element == Keyframe<Value> {
        if let index = keyframeIndex(at: time) {
            self[index].value = value
        } else {
            append(Keyframe(time: time, value: value))
            sort { $0.time < $1.time }
        }
    }
}

// MARK: - Interpolation

nonisolated extension ClipTransform {
    /// 두 트랜스폼 사이의 값. 각도도 그대로 잇는다(170도 → -170도는 반대로 340도 돈다).
    func interpolated(to other: ClipTransform, progress: Double) -> ClipTransform {
        func mix(_ from: Double, _ to: Double) -> Double {
            from + (to - from) * progress
        }
        return ClipTransform(
            centerX: mix(centerX, other.centerX),
            centerY: mix(centerY, other.centerY),
            scale: mix(scale, other.scale),
            opacity: mix(opacity, other.opacity),
            rotation: mix(rotation, other.rotation)
        )
    }
}

// MARK: - Clip

nonisolated extension Clip {
    /// 타임라인 시각에 보이는 원본 시각(속도 반영). 클립 밖 시각도 같은 비율로 늘여 계산한다(전환으로 앞뒤까지 보일 때).
    func sourceTime(atTimeline time: CMTime) -> CMTime {
        sourceRange.start + sourceTime(forTimeline: time - timelineStart)
    }

    /// 원본 시각이 놓이는 타임라인 시각.
    func timelineTime(atSource time: CMTime) -> CMTime {
        timelineStart + timelineTime(forSource: time - sourceRange.start)
    }

    /// 타임라인 시각의 트랜스폼. 트랜스폼 키프레임이 없으면 고정 값이다.
    func transform(atTimeline time: CMTime) -> ClipTransform {
        animation.transform.value(at: sourceTime(atTimeline: time)) { $0.interpolated(to: $1, progress: $2) } ?? transform
    }

    /// 타임라인 시각의 클립 음량(0~1). 음량 키프레임이 없으면 고정 값이다. 음소거는 따로 본다.
    func volume(atTimeline time: CMTime) -> Double {
        animation.volume.value(at: sourceTime(atTimeline: time)) { $0 + ($1 - $0) * $2 } ?? volume
    }

    /// 클립 안(양 끝 포함)에 보이는 키프레임의 타임라인 시각(시각 순). 타임라인 표시와 이전·다음 키프레임 이동에 쓴다.
    func keyframeTimes(of property: AnimatedProperty) -> [CMTime] {
        let sourceTimes = switch property {
        case .transform: animation.transform.map(\.time)
        case .volume: animation.volume.map(\.time)
        }
        return sourceTimes
            .filter { sourceRange.start <= $0 && $0 <= sourceRange.end }
            .map { timelineTime(atSource: $0) }
    }

    /// 클립 안에 보이는 모든 키프레임의 타임라인 시각(속성 상관없이, 겹치지 않게).
    var allKeyframeTimes: [CMTime] {
        Array(Set(AnimatedProperty.allCases.flatMap { keyframeTimes(of: $0) })).sorted()
    }

    /// 타임라인 시각에 그 속성의 키프레임이 있는지.
    func hasKeyframe(_ property: AnimatedProperty, atTimeline time: CMTime) -> Bool {
        let source = sourceTime(atTimeline: time)
        switch property {
        case .transform: return animation.transform.keyframeIndex(at: source) != nil
        case .volume: return animation.volume.keyframeIndex(at: source) != nil
        }
    }

    /// 타임라인 시각에 있는 그 속성 키프레임의 보간. 없으면 `nil`.
    func keyframeInterpolation(_ property: AnimatedProperty, atTimeline time: CMTime) -> KeyframeInterpolation? {
        let source = sourceTime(atTimeline: time)
        switch property {
        case .transform: return animation.transform.keyframeIndex(at: source).map { animation.transform[$0].interpolation }
        case .volume: return animation.volume.keyframeIndex(at: source).map { animation.volume[$0].interpolation }
        }
    }

    /// 트랜스폼을 바꾼다(#67). 트랜스폼 키프레임이 있으면 `time`(타임라인 시각)의 키프레임을 두거나 고치고, 없으면 고정 값을 바꾼다.
    mutating func setTransform(_ newValue: ClipTransform, atTimeline time: CMTime?) {
        if let time, !animation.transform.isEmpty {
            animation.transform.setKeyframe(newValue, at: sourceTime(atTimeline: time))
        } else {
            transform = newValue
        }
    }

    /// 음량을 바꾼다(#67). 규칙은 `setTransform`과 같다.
    mutating func setVolume(_ newValue: Double, atTimeline time: CMTime?) {
        if let time, !animation.volume.isEmpty {
            animation.volume.setKeyframe(newValue, at: sourceTime(atTimeline: time))
        } else {
            volume = newValue
        }
    }

    /// `time`(타임라인 시각)에 그 속성 키프레임이 있으면 지우고, 없으면 지금 보이는 값으로 둔다(#67, 인스펙터 ◆ 버튼).
    /// 마지막 키프레임을 지우면 그때 값이 고정 값이 된다.
    mutating func toggleKeyframe(_ property: AnimatedProperty, atTimeline time: CMTime) {
        let source = sourceTime(atTimeline: time)
        switch property {
        case .transform:
            let current = transform(atTimeline: time)
            if let index = animation.transform.keyframeIndex(at: source) {
                animation.transform.remove(at: index)
                if animation.transform.isEmpty {
                    transform = current
                }
            } else {
                animation.transform.setKeyframe(current, at: source)
            }
        case .volume:
            let current = volume(atTimeline: time)
            if let index = animation.volume.keyframeIndex(at: source) {
                animation.volume.remove(at: index)
                if animation.volume.isEmpty {
                    volume = current
                }
            } else {
                animation.volume.setKeyframe(current, at: source)
            }
        }
    }

    /// `time`의 그 속성 키프레임 보간을 바꾼다. 키프레임이 없으면 그대로다.
    mutating func setKeyframeInterpolation(_ interpolation: KeyframeInterpolation, for property: AnimatedProperty, atTimeline time: CMTime) {
        let source = sourceTime(atTimeline: time)
        switch property {
        case .transform:
            if let index = animation.transform.keyframeIndex(at: source) {
                animation.transform[index].interpolation = interpolation
            }
        case .volume:
            if let index = animation.volume.keyframeIndex(at: source) {
                animation.volume[index].interpolation = interpolation
            }
        }
    }

    /// 그 속성의 키프레임을 모두 지운다. `time`에 보이던 값이 고정 값이 된다.
    mutating func clearKeyframes(_ property: AnimatedProperty, atTimeline time: CMTime) {
        switch property {
        case .transform:
            transform = transform(atTimeline: time)
            animation.transform = []
        case .volume:
            volume = volume(atTimeline: time)
            animation.volume = []
        }
    }
}
