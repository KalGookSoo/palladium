import CoreMedia
import Foundation

/// 인트로만 실제 영상을 가리키고, 나머지 원본 URL은 실제 파일이 없는 자리표시다.
nonisolated enum SampleData {
    /// 로컬에만 두고 git에서 제외한 palladium/samples/sample.mov가 빌드 시 앱 번들에 들어오면 그 파일을 가리키고, 없으면 자리표시 경로가 된다.
    static let introVideo = MediaAsset(
        id: UUID(),
        name: "intro.mov",
        sourceURL: Bundle.main.url(forResource: "sample", withExtension: "mov") ?? URL(filePath: "/samples/intro.mov"),
        kind: .video,
        duration: seconds(10)
    )

    static let bRollVideo = MediaAsset(
        id: UUID(),
        name: "b-roll.mov",
        sourceURL: URL(filePath: "/samples/b-roll.mov"),
        kind: .video,
        duration: seconds(20)
    )

    static let backgroundMusic = MediaAsset(
        id: UUID(),
        name: "background-music.m4a",
        sourceURL: URL(filePath: "/samples/background-music.m4a"),
        kind: .audio,
        duration: seconds(60)
    )

    /// 배경음악은 폴더에 넣지 않아 "분류 안 됨" 상태를 함께 보여준다.
    static let footageFolder = MediaFolder(id: UUID(), name: "촬영본", assetIDs: [introVideo.id, bRollVideo.id])

    static let videoTrack = Track(
        id: UUID(),
        kind: .video,
        clips: [
            makeClip(asset: introVideo, sourceStart: 0, duration: 8, timelineStart: 0),
            makeClip(asset: bRollVideo, sourceStart: 2, duration: 10, timelineStart: 8),
        ]
    )

    static let audioTrack = Track(
        id: UUID(),
        kind: .audio,
        clips: [
            makeClip(asset: backgroundMusic, sourceStart: 0, duration: 18, timelineStart: 0),
        ]
    )

    static let mainSequence = EditSequence(id: UUID(), name: "통합본", tracks: [videoTrack, audioTrack])

    static let project: Project = {
        guard let project = Project(
            name: "샘플 프로젝트",
            assets: [introVideo, bRollVideo, backgroundMusic],
            folders: [footageFolder],
            sequences: [mainSequence]
        ) else {
            preconditionFailure("시퀀스를 하나 넘겼으므로 샘플 Project 생성은 실패할 수 없다")
        }
        return project
    }()

    // MARK: - Helpers

    private static func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: standardTimescale)
    }

    private static func makeClip(asset: MediaAsset, sourceStart: Double, duration: Double, timelineStart: Double) -> Clip {
        let sourceRange = CMTimeRange(start: seconds(sourceStart), duration: seconds(duration))
        guard let clip = Clip(assetID: asset.id, sourceRange: sourceRange, timelineStart: seconds(timelineStart)) else {
            preconditionFailure("샘플 클립 값이 Clip 불변식을 어긴다: \(asset.name)")
        }
        return clip
    }
}
