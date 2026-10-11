import CoreMedia
import Foundation

/// 샘플 프로젝트 둘러보기(#63)의 단계. 완료는 화면 조작이 아니라 프로젝트 상태로 판단해, 단축키·메뉴 어느 쪽으로 해도 체크된다.
/// 내보내기만 프로젝트를 바꾸지 않아 따로 기록한 값(`exported`)으로 판단한다.
nonisolated enum TourStep: String, CaseIterable {
    /// 원본을 타임라인으로 끌어다 놓기.
    case place
    /// 재생 헤드에서 클립 자르기(⌘B).
    case split
    /// 클립 끝을 끌어 트림하기.
    case trim
    /// 두 클립 사이에 전환 넣기.
    case transition
    /// 자막 넣기(T).
    case subtitle
    /// 영상 소리 줄이기.
    case volume
    /// 로고를 위 트랙에 얹고 크기 줄이기.
    case overlay
    /// 얼굴 가리기(마스크).
    case mask
    /// 내보내기(⌘E).
    case export
}

// MARK: - Queries

nonisolated extension TourStep {
    /// 이 단계를 해냈는지. 프로젝트의 모든 시퀀스를 본다.
    func isCompleted(in project: Project, exported: Bool) -> Bool {
        let tracks = project.sequences.flatMap(\.tracks)
        let clips = tracks.flatMap(\.clips)
        switch self {
        case .place:
            return !clips.isEmpty
        case .split:
            return tracks.contains { Self.hasSplit(in: $0) }
        case .trim:
            return tracks.contains { Self.hasTrim(in: $0, assets: project.assets) }
        case .transition:
            return clips.contains { $0.transitionIn != nil }
        case .subtitle:
            return project.sequences.contains { !$0.subtitles.isEmpty }
        case .volume:
            return clips.contains { clip in
                (clip.volume < 1 || clip.isMuted) && project.assets.first { $0.id == clip.assetID }?.kind == .video
            }
        case .overlay:
            return project.sequences.contains { Self.hasShrunkOverlay(in: $0, assets: project.assets) }
        case .mask:
            return project.sequences.contains { !$0.masks.isEmpty }
        case .export:
            return exported
        }
    }

    /// 자른 흔적: 같은 원본의 두 클립이 원본에서 이어지는 구간을 나눠 가진다.
    private static func hasSplit(in track: Track) -> Bool {
        track.clips.contains { clip in
            track.clips.contains { $0.id != clip.id && $0.assetID == clip.assetID && $0.sourceRange.start == clip.sourceRange.end }
        }
    }

    /// 트림한 흔적: 원본의 처음(또는 끝)이 빠진 클립이 있고, 그 자리를 같은 원본의 다른 클립이 잇지 않는다(자르기만 한 조각과 구분).
    private static func hasTrim(in track: Track, assets: [MediaAsset]) -> Bool {
        track.clips.contains { clip in
            guard let asset = assets.first(where: { $0.id == clip.assetID }), asset.isTrimmable else { return false }
            let full = asset.usedRange ?? CMTimeRange(start: .zero, duration: asset.duration)
            let siblings = track.clips.filter { $0.id != clip.id && $0.assetID == clip.assetID }
            let cutStart = clip.sourceRange.start > full.start && !siblings.contains { $0.sourceRange.end == clip.sourceRange.start }
            let cutEnd = clip.sourceRange.end < full.end && !siblings.contains { $0.sourceRange.start == clip.sourceRange.end }
            return cutStart || cutEnd
        }
    }

    /// 맨 아래가 아닌 영상 트랙에 이미지 클립을 얹고 크기를 줄였다.
    private static func hasShrunkOverlay(in sequence: EditSequence, assets: [MediaAsset]) -> Bool {
        let videoTracks = sequence.tracks.filter { $0.kind == .video }
        // 새 영상 트랙은 위쪽(앞)에 생기므로 맨 뒤가 메인 트랙이다.
        return videoTracks.dropLast().contains { track in
            track.clips.contains { clip in
                clip.transform.scale < 1 && assets.first { $0.id == clip.assetID }?.kind == .image
            }
        }
    }
}
