import AVFoundation
import CoreMedia
import Foundation
import ImageIO
@testable import palladium
import SwiftData
import Testing

/// 샘플 프로젝트 둘러보기(#63): 샘플 미디어 만들기, 둘러보기 프로젝트 만들기, 단계 완료 판단, 진행 기록.
@MainActor
struct TourTests {
    private let container: ModelContainer
    private let repository: SwiftDataProjectRepository

    init() throws {
        container = try ModelContainer(
            for: ProjectRecord.self, ProjectBackupRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // 자동 저장 타이머가 테스트가 끝나 사라진 컨테이너에 불리면 앱이 멈추므로 끈다.
        container.mainContext.autosaveEnabled = false
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    // MARK: - 샘플 미디어·프로젝트

    @Test("샘플 미디어는 네트워크 없이 가로 영상 2개·세로 영상 1개·로고·배경음악을 만들고, 이미 있으면 다시 만들지 않는다")
    func generateSampleMedia() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let urls = try await SampleMediaGenerator.makeAll(in: directory)
        #expect(urls.map(\.lastPathComponent) == ["바다.mov", "도시.mov", "세로 영상.mov", "로고.png", "배경음악.m4a"])

        let landscape = try await videoSize(of: urls[0])
        #expect(landscape == CGSize(width: 1280, height: 720))
        let portrait = try await videoSize(of: urls[2])
        #expect(portrait == CGSize(width: 720, height: 1280))
        let videoDuration = try await AVURLAsset(url: urls[0]).load(.duration)
        #expect(abs(videoDuration.seconds - 6) < 0.1)

        let logo = try #require(CGImageSourceCreateWithURL(urls[3] as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(logo.width == 600 && logo.alphaInfo != .none)

        let musicDuration = try await AVURLAsset(url: urls[4]).load(.duration)
        #expect(abs(musicDuration.seconds - SampleMediaGenerator.musicSeconds) < 0.2)

        // 다시 부르면 파일을 다시 쓰지 않는다.
        let modified = try FileManager.default.attributesOfItem(atPath: urls[0].path)[.modificationDate] as? Date
        _ = try await SampleMediaGenerator.makeAll(in: directory)
        #expect(try FileManager.default.attributesOfItem(atPath: urls[0].path)[.modificationDate] as? Date == modified)
    }

    @Test("둘러보기 프로젝트는 샘플 원본 5개를 \"샘플\" 폴더에 담고 빈 시퀀스로 저장되며, 둘러보기 프로젝트로 기록된다")
    func makeTourProject() async throws {
        let progress = try TourProgress(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        let projectID = try await SampleProjectFactory.makeTourProject(using: repository, progress: progress, directory: directory)

        let project = try #require(try repository.project(id: projectID))
        #expect(project.name == SampleProjectFactory.projectName)
        #expect(project.assets.count == 5)
        #expect(project.assets.map(\.kind) == [.video, .video, .video, .image, .audio])
        #expect(project.folders.map(\.name) == [SampleProjectFactory.folderName])
        #expect(project.folders.first?.assetIDs.count == 5)
        #expect(project.sequences.count == 1 && project.sequences[0].tracks.isEmpty)
        #expect(progress.isTourProject(projectID))
        #expect(progress.showsChecklist(for: projectID))
        #expect(TourStep.allCases.allSatisfy { !$0.isCompleted(in: project, exported: false) })
    }

    // MARK: - 단계 완료

    @Test("편집기로 한 편집에 따라 둘러보기 단계가 하나씩 체크된다")
    func stepsFollowProjectState() throws {
        let video = asset(.video, seconds: 6)
        let other = asset(.video, seconds: 6)
        let logo = asset(.image, seconds: 5)
        let created = try repository.createProject(named: "둘러보기")
        var initial = created
        initial.assets = [video, other, logo]
        try repository.save(initial)
        let editor = ProjectEditor(project: initial, repository: repository)
        func done(_ step: TourStep, exported: Bool = false) -> Bool {
            step.isCompleted(in: editor.project, exported: exported)
        }

        let first = try #require(editor.placeAsset(video.id, onTrack: nil, at: .zero))
        #expect(done(.place))
        #expect(!done(.split) && !done(.trim))

        // 자르기만 하면 트림으로 보지 않는다.
        editor.splitClips([first], at: seconds(3))
        #expect(done(.split))
        #expect(!done(.trim))

        let second = try #require(editor.placeAsset(other.id, onTrack: nil, at: seconds(6)))
        editor.trimClip(second, edge: .end, by: seconds(-1))
        #expect(done(.trim))

        editor.setTransition(ClipTransition(kind: .dissolve, duration: seconds(1)), forClip: second)
        #expect(done(.transition))

        editor.addSubtitle(at: .zero)
        #expect(done(.subtitle))

        editor.setClipAudio(volume: 0.5, isMuted: false, for: first)
        #expect(done(.volume))

        // 로고를 메인 트랙에 얹기만 하거나 크기를 줄이지 않으면 아직이다.
        let overlayTrack = editor.addTrack(kind: .video)
        let logoClip = try #require(editor.placeAsset(logo.id, onTrack: overlayTrack, at: .zero))
        #expect(!done(.overlay))
        editor.setTransform(ClipTransform(scale: 0.3), for: logoClip)
        #expect(done(.overlay))

        editor.addMask(at: .zero)
        #expect(done(.mask))

        #expect(!done(.export))
        #expect(done(.export, exported: true))
    }

    // MARK: - 진행 기록

    @Test("내보내기 기록은 둘러보기 프로젝트에만 남고, 목록을 닫았다 다시 열 수 있으며 앱을 다시 켜도 남는다")
    func progressStore() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let progress = TourProgress(defaults: defaults)
        let tourID = UUID()
        let otherID = UUID()

        progress.registerTourProject(tourID)
        progress.markExported(otherID)
        progress.markExported(tourID)
        #expect(progress.hasExported(tourID) && !progress.hasExported(otherID))
        #expect(!progress.showsChecklist(for: otherID))

        progress.setChecklistHidden(true, for: tourID)
        #expect(!progress.showsChecklist(for: tourID))

        let reopened = TourProgress(defaults: defaults)
        #expect(reopened.isTourProject(tourID) && reopened.hasExported(tourID) && !reopened.showsChecklist(for: tourID))
        reopened.setChecklistHidden(false, for: tourID)
        #expect(reopened.showsChecklist(for: tourID))
    }

    // MARK: - Helpers

    private func asset(_ kind: MediaKind, seconds value: Double) -> MediaAsset {
        MediaAsset(id: UUID(), name: "\(kind)", sourceURL: URL(filePath: "/tmp/\(UUID().uuidString)"), kind: kind, duration: seconds(value))
    }

    private func videoSize(of url: URL) async throws -> CGSize? {
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        return try await track?.load(.naturalSize)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }
}
