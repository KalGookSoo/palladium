import SwiftUI

/// 내보내기 코덱·해상도 고르기. 저장 창·여러 시퀀스 내보내기·환경설정이 같은 값을 쓴다(마지막에 고른 값이 다음 기본값).
struct ExportOptionsView: View {
    @AppStorage(AppPreferences.exportCodecKey) private var codec = ExportCodec.defaultValue
    @AppStorage(AppPreferences.exportResolutionKey) private var resolution = ExportResolution.defaultValue

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
    }

    /// 지금 고른 코덱·해상도.
    static var current: (codec: ExportCodec, resolution: ExportResolution) {
        let defaults = UserDefaults.standard
        return (
            defaults.string(forKey: AppPreferences.exportCodecKey).flatMap(ExportCodec.init(rawValue:)) ?? .defaultValue,
            defaults.string(forKey: AppPreferences.exportResolutionKey).flatMap(ExportResolution.init(rawValue:)) ?? .defaultValue
        )
    }
}
