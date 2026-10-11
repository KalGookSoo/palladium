import AVFoundation
import Foundation
import MediaToolbox

/// 오디오 이펙트(#74)를 샘플마다 적용하는 신호 처리기. 채널마다 상태(필터 기억·잔향·게이트)를 따로 둔다.
/// 순서: 저음 웅웅거림 깎기 → 노이즈 게이트 → 이퀄라이저(저·중·고) → 게인 → 잔향.
final nonisolated class AudioEffectProcessor {
    private let effects: AudioEffects
    private var channels: [ChannelState]
    private let gainFactor: Float
    private let gateThreshold: Float?
    private let gateAttack: Float
    private let gateRelease: Float
    private let envelopeRelease: Float

    init(effects: AudioEffects, sampleRate: Double, channelCount: Int) {
        self.effects = effects
        gainFactor = Float(pow(10, effects.gain / 20))
        gateThreshold = effects.gateThreshold.map { Float(pow(10, $0 / 20)) }
        // 게이트는 빨리 열고(5ms) 천천히 닫는다(80ms). 엔벌로프는 100ms에 걸쳐 내려간다.
        gateAttack = Self.coefficient(milliseconds: 5, sampleRate: sampleRate)
        gateRelease = Self.coefficient(milliseconds: 80, sampleRate: sampleRate)
        envelopeRelease = Self.coefficient(milliseconds: 100, sampleRate: sampleRate)
        channels = (0 ..< max(channelCount, 1)).map { index in
            ChannelState(effects: effects, sampleRate: sampleRate, channelIndex: index)
        }
    }

    /// 샘플 하나를 처리한다. `channel`은 0부터다(채널 수를 넘으면 마지막 채널 상태를 쓴다).
    func process(_ sample: Float, channel: Int) -> Float {
        let index = min(channel, channels.count - 1)
        var value = sample
        if effects.cutsLowRumble {
            value = channels[index].rumble.process(value)
        }
        if let gateThreshold {
            let level = abs(value)
            let envelope = channels[index].envelope
            channels[index].envelope = level > envelope ? level : envelope * envelopeRelease + level * (1 - envelopeRelease)
            // 문턱 아래면 -24dB로 줄인다(완전히 끊으면 숨소리가 툭툭 끊겨 들린다).
            let target: Float = channels[index].envelope >= gateThreshold ? 1 : 0.063
            let coefficient = target > channels[index].gateGain ? gateAttack : gateRelease
            channels[index].gateGain = target + (channels[index].gateGain - target) * coefficient
            value *= channels[index].gateGain
        }
        if effects.lowGain != 0 {
            value = channels[index].low.process(value)
        }
        if effects.midGain != 0 {
            value = channels[index].mid.process(value)
        }
        if effects.highGain != 0 {
            value = channels[index].high.process(value)
        }
        value *= gainFactor
        if effects.reverb > 0 {
            let mix = Float(effects.reverb)
            let wet = channels[index].reverb.process(value)
            value = value * (1 - mix * 0.5) + wet * mix
        }
        return value
    }

    /// 지수 감쇠 계수. 이만큼의 시간에 63%쯤 따라간다.
    private static func coefficient(milliseconds: Double, sampleRate: Double) -> Float {
        Float(exp(-1 / (milliseconds / 1000 * max(sampleRate, 1))))
    }

    private struct ChannelState {
        var rumble: Biquad
        var low: Biquad
        var mid: Biquad
        var high: Biquad
        var reverb: Reverb
        var envelope: Float = 0
        var gateGain: Float = 1

        init(effects: AudioEffects, sampleRate: Double, channelIndex: Int) {
            rumble = .highPass(frequency: AudioEffects.rumbleCutoff, sampleRate: sampleRate)
            low = .lowShelf(frequency: AudioEffects.lowFrequency, gain: effects.lowGain, sampleRate: sampleRate)
            mid = .peaking(frequency: AudioEffects.midFrequency, gain: effects.midGain, sampleRate: sampleRate)
            high = .highShelf(frequency: AudioEffects.highFrequency, gain: effects.highGain, sampleRate: sampleRate)
            // 오른쪽 채널은 지연을 조금 달리해 잔향이 양옆으로 퍼지게 한다.
            reverb = Reverb(sampleRate: sampleRate, spread: channelIndex * 23)
        }
    }
}

// MARK: - Biquad

/// 2차 IIR 필터(RBJ 오디오 EQ 요리책 공식). 전치 직접형 II로 계산한다.
nonisolated struct Biquad {
    private var b0: Float
    private var b1: Float
    private var b2: Float
    private var a1: Float
    private var a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = Float(b0 / a0)
        self.b1 = Float(b1 / a0)
        self.b2 = Float(b2 / a0)
        self.a1 = Float(a1 / a0)
        self.a2 = Float(a2 / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    private static func parameters(frequency: Double, sampleRate: Double, q: Double) -> (cos: Double, alpha: Double) {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        return (cos(w0), sin(w0) / (2 * q))
    }

    static func highPass(frequency: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let (cosine, alpha) = parameters(frequency: frequency, sampleRate: sampleRate, q: q)
        return Biquad(b0: (1 + cosine) / 2, b1: -(1 + cosine), b2: (1 + cosine) / 2, a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha)
    }

    static func peaking(frequency: Double, gain: Double, sampleRate: Double, q: Double = 1) -> Biquad {
        let (cosine, alpha) = parameters(frequency: frequency, sampleRate: sampleRate, q: q)
        let a = pow(10, gain / 40)
        return Biquad(b0: 1 + alpha * a, b1: -2 * cosine, b2: 1 - alpha * a, a0: 1 + alpha / a, a1: -2 * cosine, a2: 1 - alpha / a)
    }

    static func lowShelf(frequency: Double, gain: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let (cosine, alpha) = parameters(frequency: frequency, sampleRate: sampleRate, q: q)
        let a = pow(10, gain / 40)
        let shelf = 2 * a.squareRoot() * alpha
        return Biquad(
            b0: a * ((a + 1) - (a - 1) * cosine + shelf),
            b1: 2 * a * ((a - 1) - (a + 1) * cosine),
            b2: a * ((a + 1) - (a - 1) * cosine - shelf),
            a0: (a + 1) + (a - 1) * cosine + shelf,
            a1: -2 * ((a - 1) + (a + 1) * cosine),
            a2: (a + 1) + (a - 1) * cosine - shelf
        )
    }

    static func highShelf(frequency: Double, gain: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let (cosine, alpha) = parameters(frequency: frequency, sampleRate: sampleRate, q: q)
        let a = pow(10, gain / 40)
        let shelf = 2 * a.squareRoot() * alpha
        return Biquad(
            b0: a * ((a + 1) + (a - 1) * cosine + shelf),
            b1: -2 * a * ((a - 1) + (a + 1) * cosine),
            b2: a * ((a + 1) + (a - 1) * cosine - shelf),
            a0: (a + 1) - (a - 1) * cosine + shelf,
            a1: 2 * ((a - 1) - (a + 1) * cosine),
            a2: (a + 1) - (a - 1) * cosine - shelf
        )
    }
}

// MARK: - Reverb

/// 작은 방 잔향(Freeverb 방식을 줄인 것): 병렬 빗살 필터 4개 + 직렬 전역 통과 필터 2개.
nonisolated struct Reverb {
    private var combs: [DelayLine]
    private var allpasses: [DelayLine]
    private var combFilterStore: [Float]
    private static let combFeedback: Float = 0.82
    private static let damping: Float = 0.25
    private static let allpassFeedback: Float = 0.5

    init(sampleRate: Double, spread: Int) {
        let scale = sampleRate / 44100
        combs = [1116, 1188, 1277, 1356].map { DelayLine(length: Int(Double($0 + spread) * scale)) }
        allpasses = [556, 441].map { DelayLine(length: Int(Double($0 + spread) * scale)) }
        combFilterStore = [Float](repeating: 0, count: 4)
    }

    mutating func process(_ input: Float) -> Float {
        var sum: Float = 0
        for index in combs.indices {
            let delayed = combs[index].read()
            combFilterStore[index] = delayed * (1 - Self.damping) + combFilterStore[index] * Self.damping
            combs[index].write(input * 0.25 + combFilterStore[index] * Self.combFeedback)
            sum += delayed
        }
        var output = sum
        for index in allpasses.indices {
            let delayed = allpasses[index].read()
            let value = output + delayed * Self.allpassFeedback
            allpasses[index].write(value)
            output = delayed - value * Self.allpassFeedback
        }
        return output
    }

    private struct DelayLine {
        private var buffer: [Float]
        private var position = 0

        init(length: Int) {
            buffer = [Float](repeating: 0, count: max(length, 1))
        }

        func read() -> Float {
            buffer[position]
        }

        mutating func write(_ value: Float) {
            buffer[position] = value
            position = (position + 1) % buffer.count
        }
    }
}

// MARK: - Processing tap

/// 합성 오디오 트랙 하나에 붙이는 처리 탭(#74). 그 트랙에 놓인 클립마다의 구간과 이펙트를 알고,
/// 지금 들어온 소리의 시각에 맞는 클립의 이펙트를 적용한다. 미리보기(`AVPlayerItem.audioMix`)와 내보내기(`AVAssetReaderAudioMixOutput`)가 같은 탭을 쓴다.
final nonisolated class AudioEffectTap: @unchecked Sendable {
    struct Segment {
        let range: CMTimeRange
        let effects: AudioEffects
    }

    private let segments: [Segment]
    private var processors: [Int: AudioEffectProcessor] = [:]
    private var sampleRate = 44100.0
    private var channelCount = 2
    private var isFloat32 = false
    private var isInterleaved = false

    private init(segments: [Segment]) {
        self.segments = segments
    }

    /// 탭을 만든다. 이펙트가 있는 구간이 없으면 `nil`.
    static func make(segments: [Segment]) -> MTAudioProcessingTap? {
        let active = segments.filter { !$0.effects.isDefault }
        guard !active.isEmpty else { return nil }
        let context = AudioEffectTap(segments: active)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in Unmanaged<AudioEffectTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                Unmanaged<AudioEffectTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frameCount, _, bufferList, frameCountOut, flagsOut in
                var timeRange = CMTimeRange()
                guard MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, &timeRange, frameCountOut) == noErr else { return }
                Unmanaged<AudioEffectTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .process(bufferList, frameCount: Int(frameCountOut.pointee), at: timeRange.start)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr else {
            Unmanaged<AudioEffectTap>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        return tap
    }

    private func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate
        channelCount = Int(format.mChannelsPerFrame)
        isFloat32 = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        processors = [:]
    }

    private func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int, at time: CMTime) {
        // 32비트 실수가 아닌 형식은 건드리지 않는다(AVFoundation 오디오 믹스는 늘 실수다).
        guard isFloat32, time.isNumeric, let index = segments.firstIndex(where: { $0.range.containsTime(time) }) else { return }
        let processor = processors[index] ?? AudioEffectProcessor(effects: segments[index].effects, sampleRate: sampleRate, channelCount: channelCount)
        processors[index] = processor
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channelsInBuffer = max(Int(buffer.mNumberChannels), 1)
            let sampleCount = min(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size, frameCount * channelsInBuffer)
            for sampleIndex in 0 ..< sampleCount {
                let channel = isInterleaved ? sampleIndex % channelsInBuffer : bufferIndex
                data[sampleIndex] = processor.process(data[sampleIndex], channel: channel)
            }
        }
    }
}
