import AVFoundation
import CoreMedia
import Foundation
@testable import palladium
import Testing

/// 내보내기 안정성(#130): 진행 시간 계산, 합성 실패 기록과 실패 안내, 저장 창 없는 동영상 폴더 내보낼 곳.
struct ExportReliabilityTests {
    @Test("남은 시간은 지난 시간과 진행률로 어림하고, 처음(2% 미만)·끝에서는 어림하지 않으며, 30초 넘게 그대로면 멈춘 것으로 본다")
    func timing() throws {
        #expect(try abs(#require(ExportTiming.remaining(elapsed: 30, progress: 0.25)) - 90) < 1e-9)
        #expect(ExportTiming.remaining(elapsed: 5, progress: 0.01) == nil)
        #expect(ExportTiming.remaining(elapsed: 5, progress: 1) == nil)
        #expect(!ExportTiming.isStalled(sinceLastProgress: 29))
        #expect(ExportTiming.isStalled(sinceLastProgress: 30))
        #expect(ExportTiming.label(65) == "1:05")
        #expect(ExportTiming.label(3723) == "1:02:03")
    }

    @Test("합성 실패 기록은 개수와 처음 몇 개의 시각·클립·이유를 요약하고, 없으면 요약이 없다")
    func diagnosticsSummary() {
        let diagnostics = CompositionDiagnostics()
        #expect(diagnostics.summary == nil)
        diagnostics.record(time: CMTime(value: 125, timescale: 10), clipName: "인트로", reason: "원본 프레임을 읽지 못함")
        #expect(diagnostics.summary == "프레임 1개를 그리지 못했습니다 — 0:12.5 '인트로'(원본 프레임을 읽지 못함)")
        for index in 0 ..< 4 {
            diagnostics.record(time: CMTime(value: Int64(index), timescale: 1), clipName: nil, reason: "버퍼 없음")
        }
        #expect(diagnostics.failureCount == 5)
        #expect(diagnostics.summary?.hasSuffix("외 2개") == true)
    }

    @Test("인코딩이 실패했고 그리지 못한 프레임이 있었으면 실패 안내에 시각·클립을 붙인다")
    func failureIncludesDiagnostics() async throws {
        let redURL = try await TestMedia.makeVideo(red: 255, green: 0, blue: 0, seconds: 1)
        let red = MediaAsset(id: UUID(), name: "red.mov", sourceURL: redURL, kind: .video, duration: CMTime(value: 1, timescale: 1))
        var sequence = EditSequence(id: UUID(), name: "시퀀스", tracks: [])
        let trackID = sequence.addTrack(kind: .video)
        try sequence.place(#require(red.makeClip(at: .zero)), onTrack: trackID)
        let composition = try #require(await SequenceComposer.makeComposition(sequence: sequence, assets: [red], aspectRatio: .landscape16x9, resolveURL: \.sourceURL))
        composition.diagnostics.record(time: CMTime(value: 5, timescale: 10), clipName: "red.mov", reason: "원본 프레임을 읽지 못함")
        // 없는 폴더라 쓰기를 시작할 수 없다.
        let output = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/out.mp4")

        await #expect {
            try await SequenceExporter.export(composition, to: output) { _ in }
        } throws: { error in
            guard case let SequenceExporter.ExportError.renderFailed(_, details)? = error as? SequenceExporter.ExportError else { return false }
            return details.contains("'red.mov'") && details.contains("0:00.5")
        }
    }

    @Test("동영상 폴더 내보낼 곳은 폴더를 만들고, 같은 이름이 있으면 번호를 붙이며, 파일 이름에 쓸 수 없는 글자는 바꾼다")
    func moviesFolderDestination() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = try ExportDestination.nextMoviesFolderURL(named: "여행/브이로그 - 통합본", in: folder)
        #expect(first.lastPathComponent == "여행-브이로그 - 통합본.mp4")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        try Data().write(to: first)
        #expect(try ExportDestination.nextMoviesFolderURL(named: "여행/브이로그 - 통합본", in: folder).lastPathComponent == "여행-브이로그 - 통합본 2.mp4")
        #expect(ExportDestination.moviesFolder.path.hasSuffix("/Movies/palladium"))
        #expect(!ExportDestination.moviesFolder.path.contains("/Library/Containers/"))
    }
}
