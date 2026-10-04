import AVFoundation
import Foundation
import ImageIO
@testable import palladium
import Testing
import UniformTypeIdentifiers

struct MediaImporterTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test("파일 형식으로 원본 종류를 정하고, 미디어가 아니면 nil이다")
    func kindFollowsContentType() {
        #expect(MediaImporter.kind(of: .mpeg4Movie) == .video)
        #expect(MediaImporter.kind(of: .quickTimeMovie) == .video)
        #expect(MediaImporter.kind(of: .mp3) == .audio)
        #expect(MediaImporter.kind(of: .png) == .image)
        #expect(MediaImporter.kind(of: .plainText) == nil)
    }

    @Test("오디오는 길이를 읽고 북마크와 함께 가져온다")
    func audioIsImportedWithDurationAndBookmark() async throws {
        let url = try makeSilentAudio(named: "narration.wav", seconds: 1)

        let report = await MediaImporter.importMedia(from: [url], existingAssets: [])

        let asset = try #require(report.imported.first)
        #expect(asset.name == "narration.wav")
        #expect(asset.kind == .audio)
        #expect(abs(asset.duration.seconds - 1) < 0.01)
        #expect(asset.bookmarkData != nil)
        #expect(report.summary == nil)
    }

    @Test("이미지는 정해진 길이로 가져온다")
    func imageUsesStillDuration() async throws {
        let url = try makeImage(named: "title.png")

        let report = await MediaImporter.importMedia(from: [url], existingAssets: [])

        #expect(report.imported.first?.kind == .image)
        #expect(report.imported.first?.duration == MediaAsset.stillImageDuration)
    }

    @Test("미디어가 아닌 파일과 폴더는 이유와 함께 실패하고, 나머지는 가져온다")
    func unsupportedFilesFailIndividually() async throws {
        let text = directory.appending(path: "memo.txt")
        try Data("메모".utf8).write(to: text)
        let folder = directory.appending(path: "촬영본", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = try makeSilentAudio(named: "music.wav", seconds: 1)

        let report = await MediaImporter.importMedia(from: [text, folder, audio], existingAssets: [])

        #expect(report.imported.map(\.name) == ["music.wav"])
        #expect(report.failures == [
            MediaImportFailure(fileName: "memo.txt", reason: .unsupportedType),
            MediaImportFailure(fileName: "촬영본", reason: .folder),
        ])
        #expect(report.summary?.title == "일부 파일을 가져오지 못했습니다")
    }

    @Test("이미 가져온 파일이나 한 번에 두 번 고른 파일은 건너뛰고 기존 원본을 가리킨다")
    func duplicatesAreSkipped() async throws {
        let first = try makeSilentAudio(named: "a.wav", seconds: 1)
        let second = try makeSilentAudio(named: "b.wav", seconds: 1)
        let existing = MediaAsset(id: UUID(), name: "a.wav", sourceURL: first, kind: .audio, duration: .zero)

        let report = await MediaImporter.importMedia(from: [first, second, second], existingAssets: [existing])

        #expect(report.imported.map(\.name) == ["b.wav"])
        #expect(report.duplicateIDs == [existing.id, report.imported[0].id])
        #expect(report.summary?.title == "이미 가져온 파일입니다")
        #expect(report.summary?.message == "이미 가져온 파일 2개는 건너뛰었습니다.")
    }

    // MARK: - Helpers

    private func makeSilentAudio(named name: String, seconds: Double) throws -> URL {
        let url = directory.appending(path: name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let frameCount = AVAudioFrameCount(44100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeImage(named name: String) throws -> URL {
        let url = directory.appending(path: name)
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
