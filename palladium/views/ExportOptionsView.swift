import SwiftUI

/// 내보내기 저장 창 아래와 환경설정에 함께 쓰는 코덱·해상도·화질 선택. 고른 값은 앱 설정에 남는다.
struct ExportOptionsView: View {
    @AppStorage(AppPreferences.exportCodecKey) private var codec = ExportCodec.defaultValue
    @AppStorage(AppPreferences.exportResolutionKey) private var resolution = ExportResolution.defaultValue
    @AppStorage(AppPreferences.exportQualityKey) private var quality = ExportQuality.defaultValue
    @AppStorage(AppPreferences.exportCustomMbpsKey) private var customMbps = ExportBitRate.defaultCustomMbps

    var body: some View {
        Picker("코덱", selection: $codec) {
            ForEach(ExportCodec.allCases, id: \.self) { codec in
                Text(codec.title).tag(codec)
            }
        }
        Picker("해상도", selection: $resolution) {
            ForEach(ExportResolution.allCases, id: \.self) { resolution in
                Text(resolution.title).tag(resolution)
            }
        }
        // 화질(#77): 단계는 해상도·프레임레이트·코덱으로 비트레이트를 계산하고, 직접 입력은 Mbit/s를 그대로 쓴다.
        Picker("화질", selection: $quality) {
            ForEach(ExportQuality.allCases, id: \.self) { quality in
                Text(quality.title).tag(quality)
            }
        }
        .help("원본과 비슷하게: 시퀀스에 쓰인 영상 중 가장 높은 데이터율을 따릅니다. 높음·보통·작게: 해상도·프레임레이트에 맞춰 계산합니다(1080p 30fps H.264 기준 약 9·5.6·3.1Mbit/s)")
        // 저장 창 아래 칸은 크기가 처음에 정해져 줄이 늘면 잘리므로, 비트레이트 칸은 늘 두고 직접 입력일 때만 켠다.
        Group {
            LabeledContent("비트레이트") {
                HStack(spacing: 4) {
                    TextField("비트레이트", value: $customMbps, format: .number.precision(.fractionLength(0 ... 1)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("Mbit/s")
                        .foregroundStyle(.secondary)
                }
            }
            .help("영상 데이터율(\(Int(ExportBitRate.minimumMbps))~\(Int(ExportBitRate.maximumMbps))Mbit/s). 화질에서 \"직접 입력\"을 고르면 씁니다. 유튜브 권장: 1080p 30fps 8, 60fps 12, 4K 30fps 35~45Mbit/s")
        }
        .disabled(quality != .custom)
    }

    /// 지금 고른 내보내기 설정.
    static var current: ExportOptions {
        let defaults = UserDefaults.standard
        let storedMbps = defaults.double(forKey: AppPreferences.exportCustomMbpsKey)
        return ExportOptions(
            codec: defaults.string(forKey: AppPreferences.exportCodecKey).flatMap(ExportCodec.init(rawValue:)) ?? .defaultValue,
            resolution: defaults.string(forKey: AppPreferences.exportResolutionKey).flatMap(ExportResolution.init(rawValue:)) ?? .defaultValue,
            quality: defaults.string(forKey: AppPreferences.exportQualityKey).flatMap(ExportQuality.init(rawValue:)) ?? .defaultValue,
            customMbps: storedMbps > 0 ? storedMbps : ExportBitRate.defaultCustomMbps
        )
    }
}

/// 내보내기 한 번에 쓰는 설정.
struct ExportOptions {
    let codec: ExportCodec
    let resolution: ExportResolution
    let quality: ExportQuality
    let customMbps: Double
}
