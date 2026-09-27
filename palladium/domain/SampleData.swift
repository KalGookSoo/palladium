import CoreMedia
import Foundation

/// 미리보기(`#Preview`)와 유닛 테스트에서 함께 쓰는 샘플 데이터.
///
/// 원본 URL은 실제 파일이 없는 자리표시다.
nonisolated enum SampleData {
    /// 10초 길이의 인트로 영상 원본.
    static let introVideo = MediaAsset(
        id: UUID(),
        sourceURL: URL(filePath: "/samples/intro.mov"),
        kind: .video,
        duration: seconds(10)
    )

    /// 20초 길이의 B롤 영상 원본.
    static let bRollVideo = MediaAsset(
        id: UUID(),
        sourceURL: URL(filePath: "/samples/b-roll.mov"),
        kind: .video,
        duration: seconds(20)
    )

    /// 60초 길이의 배경음악 원본.
    static let backgroundMusic = MediaAsset(
        id: UUID(),
        sourceURL: URL(filePath: "/samples/background-music.m4a"),
        kind: .audio,
        duration: seconds(60)
    )

    /// 영상 트랙: 인트로(0~8초) 뒤에 B롤(8~18초)이 맞닿아 이어진다.
    static let videoTrack = Track(
        id: UUID(),
        kind: .video,
        clips: [
            makeClip(asset: introVideo, sourceStart: 0, duration: 8, timelineStart: 0),
            makeClip(asset: bRollVideo, sourceStart: 2, duration: 10, timelineStart: 8),
        ]
    )

    /// 오디오 트랙: 배경음악이 0~18초 구간에 깔린다.
    static let audioTrack = Track(
        id: UUID(),
        kind: .audio,
        clips: [
            makeClip(asset: backgroundMusic, sourceStart: 0, duration: 18, timelineStart: 0),
        ]
    )

    /// 영상·오디오 트랙을 하나씩 가진 "통합본" 시퀀스.
    static let mainSequence = EditSequence(id: UUID(), name: "통합본", tracks: [videoTrack, audioTrack])

    /// 위 원본과 시퀀스를 모두 담은 샘플 프로젝트. 시퀀스를 하나 넘기므로 `init?`은 항상 성공한다.
    static let project = Project(
        name: "샘플 프로젝트",
        assets: [introVideo, bRollVideo, backgroundMusic],
        sequences: [mainSequence]
    )!

    // MARK: - Helpers

    /// 초 단위 값을 `CMTime`으로 바꾼다.
    private static func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }

    /// 초 단위 값으로 클립을 만든다. 샘플 값은 모두 유효하므로 항상 성공한다.
    private static func makeClip(asset: MediaAsset, sourceStart: Double, duration: Double, timelineStart: Double) -> Clip {
        let sourceRange = CMTimeRange(start: seconds(sourceStart), duration: seconds(duration))
        return Clip(assetID: asset.id, sourceRange: sourceRange, timelineStart: seconds(timelineStart))!
    }
}
