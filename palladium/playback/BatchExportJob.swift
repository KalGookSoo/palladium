import Foundation
import Observation

/// 여러 시퀀스를 큐에 담아 순서대로 내보내는 일 하나(#6 2단계). 하나가 실패해도 나머지는 계속한다.
@Observable
final class BatchExportJob: Identifiable {
    enum State: Equatable {
        case waiting
        case exporting(Double)
        case finished
        case failed(String)
        case cancelled
    }

    @Observable
    final class Item: Identifiable {
        let id = UUID()
        let sequenceID: EditSequence.ID
        let destination: URL
        var state = State.waiting

        init(sequenceID: EditSequence.ID, destination: URL) {
            self.sequenceID = sequenceID
            self.destination = destination
        }
    }

    let id = UUID()
    let items: [Item]
    @ObservationIgnored var task: Task<Void, Never>?

    init(items: [Item]) {
        self.items = items
    }

    var isFinished: Bool {
        items.allSatisfy { item in
            switch item.state {
            case .finished, .failed, .cancelled: true
            case .waiting, .exporting: false
            }
        }
    }

    /// 항목을 순서대로 내보낸다. 취소하면 남은 항목을 모두 취소로 표시한다.
    /// `export`는 항목 하나를 내보내며 진행률(0~1)을 알린다.
    func run(export: (Item, @escaping @Sendable (Double) -> Void) async throws -> Void) async {
        for item in items {
            guard !Task.isCancelled else {
                item.state = .cancelled
                continue
            }
            item.state = .exporting(0)
            do {
                try await export(item) { fraction in
                    Task { @MainActor in
                        if case .exporting = item.state {
                            item.state = .exporting(fraction)
                        }
                    }
                }
                item.state = .finished
            } catch is CancellationError {
                item.state = .cancelled
            } catch {
                item.state = .failed(error.localizedDescription)
            }
        }
    }

    /// 시퀀스 이름으로 만든 파일 위치. 파일 이름에 쓸 수 없는 글자는 바꾸고, 이미 있는 파일이나 같은 이름은 " 2", " 3"을 붙인다.
    nonisolated static func destinations(for names: [String], in folder: URL, fileExists: (URL) -> Bool) -> [URL] {
        var used: Set<String> = []
        return names.map { name in
            let base = name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespaces)
            let safeBase = base.isEmpty ? "시퀀스" : base
            var candidate = safeBase
            var number = 2
            while used.contains(candidate.lowercased()) || fileExists(folder.appending(path: "\(candidate).mp4")) {
                candidate = "\(safeBase) \(number)"
                number += 1
            }
            used.insert(candidate.lowercased())
            return folder.appending(path: "\(candidate).mp4")
        }
    }
}
