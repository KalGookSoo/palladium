import CoreAudio

/// 지금 소리가 나가는 곳. 내레이션을 녹음할 때 원본 소리가 마이크로 새어 들어가지 않는지 판단하는 데 쓴다(#10).
nonisolated enum AudioOutputRoute {
    /// 기본 출력이 헤드폰·이어폰이면 `true`. 맥 내장 단자의 헤드폰과 블루투스 기기를 헤드폰으로 본다.
    /// 그 밖의 출력(내장 스피커, HDMI·USB 등 외부 기기)은 스피커일 수 있어 `false`로 본다(소리를 끄는 쪽이 안전하다).
    static func isHeadphonesConnected() -> Bool {
        guard let deviceID = defaultOutputDevice() else { return false }
        switch property(kAudioDevicePropertyTransportType, of: deviceID, scope: kAudioObjectPropertyScopeGlobal) {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return true
        case kAudioDeviceTransportTypeBuiltIn:
            // 내장 출력의 데이터 소스가 'hdpn'(헤드폰)이면 단자에 무언가 꽂혀 있다.
            return property(kAudioDevicePropertyDataSource, of: deviceID, scope: kAudioDevicePropertyScopeOutput) == 0x6864_706E
        default:
            return false
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private static func property(_ selector: AudioObjectPropertySelector, of deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
