import Observation
import SwiftUI

/// 진행 중인 내보내기 하나. 진행률과 결과(성공·실패)를 화면에 알린다.
@Observable
final class ExportJob: Identifiable {
    let id = UUID()
    let fileName: String
    var progress = 0.0
    private(set) var isFinished = false
    private(set) var errorMessage: String?
    @ObservationIgnored var task: Task<Void, Never>?

    init(fileName: String) {
        self.fileName = fileName
    }

    func finish(error: String?) {
        isFinished = true
        errorMessage = error
    }
}

/// 내보내는 동안 진행률을 보여주고 취소할 수 있는 시트. 끝나면 결과를 알린다.
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
            } else {
                ProgressView(value: job.progress)
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
        .frame(width: 360)
    }
}
