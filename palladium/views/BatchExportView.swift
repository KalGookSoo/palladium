import AppKit
import CoreMedia
import SwiftUI

/// 여러 시퀀스 내보내기(#6 2단계). 내보낼 시퀀스와 화면비를 고르고 폴더를 정하면 순서대로 내보내며 항목마다 진행을 보여준다.
struct BatchExportView: View {
    /// 클립이 있는 시퀀스만 고를 수 있다.
    let sequences: [EditSequence]
    let initialAspectRatio: AspectRatioPreset
    /// 시퀀스 원본 방향에 맞는 화면비. 고른 화면비와 다르면 그 시퀀스에 경고를 붙인다.
    var suggestedAspectRatio: (EditSequence) async -> AspectRatioPreset? = { _ in nil }
    /// 고른 시퀀스·화면비·폴더로 내보내기를 시작하고 그 일을 돌려준다.
    let start: ([EditSequence.ID], AspectRatioPreset, URL) -> BatchExportJob
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<EditSequence.ID> = []
    @State private var aspectRatio = AspectRatioPreset.landscape16x9
    @State private var job: BatchExportJob?
    @State private var suggestions: [EditSequence.ID: AspectRatioPreset] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if let job {
                progressList(job)
            } else {
                setup
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            aspectRatio = initialAspectRatio
            selectedIDs = Set(sequences.filter { $0.duration > .zero }.map(\.id))
        }
        .task {
            for sequence in sequences {
                suggestions[sequence.id] = await suggestedAspectRatio(sequence)
            }
        }
    }

    private var title: String {
        guard let job else { return "여러 시퀀스 내보내기" }
        return job.isFinished ? "내보내기 끝" : "내보내는 중…"
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(sequences) { sequence in
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(sequence.id) },
                    set: { isOn in
                        if isOn {
                            selectedIDs.insert(sequence.id)
                        } else {
                            selectedIDs.remove(sequence.id)
                        }
                    }
                )) {
                    HStack {
                        Text(sequence.name)
                        if let suggested = suggestions[sequence.id], suggested != aspectRatio {
                            Label("\(suggested.orientationTitle) — \(suggested.title) 권장", systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help("고른 화면비와 원본 방향이 달라 빈 곳이 검게 채워지고 영상이 작아집니다")
                        }
                        Spacer()
                        Text(Duration.seconds(sequence.duration.seconds).formatted(.time(pattern: .minuteSecond)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(sequence.duration == .zero)
            }
            .frame(height: 180)
            Picker("화면비", selection: $aspectRatio) {
                ForEach(AspectRatioPreset.allCases) { preset in
                    Text("\(preset.widthRatio):\(preset.heightRatio)").tag(preset)
                }
            }
            ExportOptionsView()
            Text("고른 폴더에 시퀀스 이름으로 MP4 파일을 만듭니다. 프레임레이트는 원본을 따르고, 같은 이름의 파일이 있으면 덮어쓰지 않고 번호를 붙입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("폴더 선택 후 내보내기…", action: chooseFolder)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.isEmpty)
            }
        }
    }

    private func progressList(_ job: BatchExportJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(job.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.destination.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        stateLabel(item.state)
                    }
                    if case let .exporting(progress) = item.state {
                        ProgressView(value: progress)
                    }
                    if case let .failed(message) = item.state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            HStack {
                Spacer()
                if job.isFinished {
                    Button("Finder에서 보기") {
                        let finished = job.items.filter { $0.state == .finished }.map(\.destination)
                        NSWorkspace.shared.activateFileViewerSelecting(finished)
                    }
                    .disabled(!job.items.contains { $0.state == .finished })
                    Button("확인") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("모두 취소") { job.task?.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    @ViewBuilder
    private func stateLabel(_ state: BatchExportJob.State) -> some View {
        switch state {
        case .waiting:
            Text("대기").foregroundStyle(.secondary)
        case let .exporting(progress):
            Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        case .finished:
            Label("완료", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Text("취소됨").foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "내보내기"
        panel.message = "시퀀스 \(selectedIDs.count)개를 내보낼 폴더를 고르세요."
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            // 목록 순서대로 내보낸다.
            let orderedIDs = sequences.map(\.id).filter { selectedIDs.contains($0) }
            job = start(orderedIDs, aspectRatio, folder)
        }
    }
}
