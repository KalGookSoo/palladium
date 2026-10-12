import Observation
import SwiftUI

/// 진행 중인 내보내기 하나. 진행률과 결과(성공·실패), 걸린 시간을 화면에 알린다.
@Observable
final class ExportJob: Identifiable {
    let id = UUID()
    let fileName: String
    var progress = 0.0 {
        didSet {
            if progress != oldValue {
                lastProgressAt = .now
            }
        }
    }

    private(set) var isFinished = false
    private(set) var errorMessage: String?
    /// 끝났지만 일부 프레임을 그리지 못했을 때의 안내(#130).
    private(set) var warning: String?
    /// 시작한 때와 진행률이 마지막으로 바뀐 때(#130). 지난·남은 시간과 멈춤 안내에 쓴다.
    let startedAt = Date.now
    private(set) var lastProgressAt = Date.now
    @ObservationIgnored var task: Task<Void, Never>?

    init(fileName: String) {
        self.fileName = fileName
    }

    func finish(error: String?, warning: String? = nil) {
        isFinished = true
        errorMessage = error
        self.warning = warning
    }
}

/// 내보내는 동안 진행률·지난 시간·남은 예상 시간을 보여주고 취소할 수 있는 시트(#130). 진행률이 30초 넘게 그대로면 응답이 없다고 알린다.
/// 끝나면 결과를 알리고, 실패하면 이유(그리지 못한 시각·클립 포함)를 보여준다.
struct ExportProgressView: View {
    let job: ExportJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(job.isFinished ? (job.errorMessage == nil ? "내보내기 완료" : "내보내지 못했습니다") : "내보내는 중…")
                .font(.headline)
            Text(job.fileName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let errorMessage = job.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if job.isFinished {
                if let warning = job.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView(value: job.progress)
                // 1초마다 지난 시간·남은 시간·멈춤 여부를 다시 계산한다.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timing(at: context.date)
                }
            }
            HStack {
                Spacer()
                if job.isFinished {
                    Button("확인") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("취소") { job.task?.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder
    private func timing(at now: Date) -> some View {
        let elapsed = now.timeIntervalSince(job.startedAt)
        let remaining = ExportTiming.remaining(elapsed: elapsed, progress: job.progress)
        HStack {
            Text(job.progress, format: .percent.precision(.fractionLength(0)))
            Spacer()
            Text("지난 시간 \(ExportTiming.label(elapsed))" + (remaining.map { " · 남은 시간 약 \(ExportTiming.label($0))" } ?? ""))
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        if ExportTiming.isStalled(sinceLastProgress: now.timeIntervalSince(job.lastProgressAt)) {
            Label("\(ExportTiming.label(now.timeIntervalSince(job.lastProgressAt))) 동안 진행이 없습니다. 원본을 읽는 데 오래 걸리고 있거나 멈췄을 수 있습니다 — 취소하고 다시 시도할 수 있습니다.", systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
