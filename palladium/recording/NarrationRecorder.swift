import AVFoundation
import CoreMedia
import Observation
import OSLog

/// 마이크로 내레이션을 녹음한다(#10). 재생은 하지 않고 녹음 파일만 만든다. 미리보기 재생·음소거와
/// 녹음 결과를 프로젝트에 넣는 일은 편집 창(`MainWindowView`)과 편집기(`ProjectEditor.addNarration`)가 한다.
@Observable
final class NarrationRecorder {
    enum RecordingError: Error, LocalizedError {
        case permissionDenied
        case cannotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "마이크 사용이 허용되지 않았습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 palladium을 허용하세요."
            case .cannotStart:
                "녹음을 시작할 수 없습니다. 다른 앱이 마이크를 쓰고 있는지 확인하세요."
            }
        }
    }

    /// 녹음 중이면 녹음을 시작한 시퀀스 시각.
    private(set) var startTime: CMTime?
    private(set) var startedAt: Date?
    @ObservationIgnored private var recorder: AVAudioRecorder?

    var isRecording: Bool {
        recorder != nil
    }

    /// 마이크 권한을 (처음이면) 묻고 녹음을 시작한다. `time`은 결과 클립을 놓을 시퀀스 시각이다.
    func start(at time: CMTime) async throws {
        guard recorder == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecordingError.permissionDenied
        }
        let url = try Self.newRecordingURL()
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ])
        guard recorder.record() else {
            throw RecordingError.cannotStart
        }
        self.recorder = recorder
        startTime = time
        startedAt = .now
        Logger.narration.notice("내레이션 녹음 시작: \(url.lastPathComponent, privacy: .public)")
    }

    /// 녹음을 멈추고 파일과 시작 시각을 돌려준다. 녹음 중이 아니면 `nil`.
    func stop() -> (url: URL, startTime: CMTime)? {
        guard let recorder, let startTime else { return nil }
        recorder.stop()
        self.recorder = nil
        self.startTime = nil
        startedAt = nil
        Logger.narration.notice("내레이션 녹음 끝: \(recorder.url.lastPathComponent, privacy: .public)")
        return (recorder.url, startTime)
    }

    /// 앱 컨테이너의 Application Support/Narrations 아래 새 파일. 원본을 복사하지 않는 앱이라 녹음 파일은 지우지 않고 남긴다.
    private static func newRecordingURL() throws -> URL {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Narrations", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current,
            calendar: .current
        ))
        return folder.appending(path: "내레이션 \(stamp).m4a")
    }
}
