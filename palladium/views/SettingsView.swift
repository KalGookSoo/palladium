import SwiftUI

/// 앱 전역 설정의 저장 키. 값은 `UserDefaults`에 두어 앱을 다시 켜도 유지된다.
enum AppPreferences {
    static let backupIntervalSecondsKey = "backupIntervalSeconds"
    static let defaultAspectRatioKey = "defaultAspectRatio"
    static let timelineShowsFilmstripKey = "timelineShowsFilmstrip"
    static let timelineShowsWaveformKey = "timelineShowsWaveform"
}

/// palladium > 설정…(⌘,)에서 여는 환경설정 창. 바꾸면 바로 저장된다(별도 저장 버튼 없음).
/// 프록시 임계값(#43)은 그 기능이 생길 때 여기에 더한다.
struct SettingsView: View {
    @AppStorage(AppPreferences.backupIntervalSecondsKey) private var backupIntervalSeconds = Int(BackupPolicy.defaultInterval.components.seconds)
    @AppStorage(AppPreferences.defaultAspectRatioKey) private var defaultAspectRatio = AspectRatioPreset.landscape16x9

    var body: some View {
        Form {
            Section {
                Picker("새 편집 창의 화면비", selection: $defaultAspectRatio) {
                    ForEach(AspectRatioPreset.allCases) { preset in
                        Text("\(preset.widthRatio):\(preset.heightRatio)").tag(preset)
                    }
                }
            } footer: {
                Text("편집 창을 열 때 툴바의 화면비가 이 값으로 시작합니다. 내보내기는 툴바에서 고른 화면비로 합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("저장하지 않은 변경 백업 간격", selection: $backupIntervalSeconds) {
                    ForEach(BackupPolicy.intervalChoicesInSeconds, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))).tag(seconds)
                    }
                }
            } footer: {
                Text("저장하지 않은 변경을 이 간격마다 백업해, 앱이 비정상 종료돼도 다시 열 때 복구할 수 있습니다. 열려 있는 프로젝트에는 다음 백업부터 반영됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
