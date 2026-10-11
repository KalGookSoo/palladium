import Foundation

/// 클립 소리에 거는 기본 오디오 이펙트(#74). 기본값이면 원본 소리 그대로다.
/// 미리보기·내보내기가 같은 오디오 믹스(처리 탭)로 적용한다.
nonisolated struct AudioEffects {
    /// 저음·중음·고음 이퀄라이저(dB, -12~+12). 0이면 그대로.
    var lowGain = 0.0
    var midGain = 0.0
    var highGain = 0.0
    /// 80Hz 아래 웅웅거림(바람·책상 울림)을 깎는다.
    var cutsLowRumble = false
    /// 잔향 섞는 정도(0~1). 0이면 없다.
    var reverb = 0.0
    /// 노이즈 게이트(0~1). 0이면 끄고, 클수록 더 큰 소리까지 조용한 잡음으로 보고 줄인다.
    var noiseGate = 0.0
    /// 전체 소리 키우기·줄이기(dB, -12~+12). 클립 음량(0~100%)과 달리 원본보다 크게 할 수 있다.
    var gain = 0.0

    static let gainRange = -12.0 ... 12.0
    /// 이퀄라이저 기준 주파수(Hz).
    static let lowFrequency = 200.0
    static let midFrequency = 1000.0
    static let highFrequency = 5000.0
    static let rumbleCutoff = 80.0
    /// 노이즈 게이트 세기 0~1이 가리키는 문턱(dBFS).
    static let gateThresholdRange = -70.0 ... -30.0
}

nonisolated extension AudioEffects: Equatable {}

// MARK: - Queries

nonisolated extension AudioEffects {
    var isDefault: Bool {
        self == AudioEffects()
    }

    /// 노이즈 게이트 문턱(dBFS). 꺼져 있으면 `nil`.
    var gateThreshold: Double? {
        guard noiseGate > 0 else { return nil }
        return Self.gateThresholdRange.lowerBound + (Self.gateThresholdRange.upperBound - Self.gateThresholdRange.lowerBound) * noiseGate
    }
}

// MARK: - Commands

nonisolated extension AudioEffects {
    mutating func clamp() {
        lowGain = min(max(lowGain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        midGain = min(max(midGain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        highGain = min(max(highGain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        gain = min(max(gain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        reverb = min(max(reverb, 0), 1)
        noiseGate = min(max(noiseGate, 0), 1)
    }
}
