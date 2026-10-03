import CoreMedia
import Foundation
import OSLog
import SwiftData

// MARK: - Domain → Record

extension ProjectRecord {
    /// 기존 하위 레코드를 지우고 도메인 프로젝트의 내용으로 다시 채운다.
    /// 무엇이 바뀌었는지 비교하는 대신 통째로 교체해, 빠뜨린 삭제·순서 변경이 남지 않게 한다.
    func replaceContent(with project: Project, modifiedAt: Date, in modelContext: ModelContext) {
        assets.forEach(modelContext.delete)
        folders.forEach(modelContext.delete)
        sequences.forEach(modelContext.delete)

        name = project.name
        self.modifiedAt = modifiedAt
        assetCount = project.assets.count
        sequenceCount = project.sequences.count
        assets = project.assets.enumerated().map { index, asset in
            MediaAssetRecord(
                id: asset.id,
                sortIndex: index,
                name: asset.name,
                sourceURL: asset.sourceURL,
                kindRawValue: asset.kind.rawValue,
                durationValue: asset.duration.value,
                durationTimescale: asset.duration.timescale
            )
        }
        folders = project.folders.enumerated().map { index, folder in
            MediaFolderRecord(id: folder.id, sortIndex: index, name: folder.name, assetIDs: folder.assetIDs)
        }
        sequences = project.sequences.enumerated().map { index, sequence in
            SequenceRecord.make(from: sequence, sortIndex: index)
        }
    }
}

private extension SequenceRecord {
    static func make(from sequence: EditSequence, sortIndex: Int) -> SequenceRecord {
        let record = SequenceRecord(id: sequence.id, sortIndex: sortIndex, name: sequence.name)
        record.tracks = sequence.tracks.enumerated().map { trackIndex, track in
            let trackRecord = TrackRecord(id: track.id, sortIndex: trackIndex, kindRawValue: track.kind.rawValue)
            trackRecord.clips = track.clips.enumerated().map { clipIndex, clip in
                ClipRecord(
                    id: clip.id,
                    sortIndex: clipIndex,
                    assetID: clip.assetID,
                    sourceStartValue: clip.sourceRange.start.value,
                    sourceStartTimescale: clip.sourceRange.start.timescale,
                    sourceDurationValue: clip.sourceRange.duration.value,
                    sourceDurationTimescale: clip.sourceRange.duration.timescale,
                    timelineStartValue: clip.timelineStart.value,
                    timelineStartTimescale: clip.timelineStart.timescale
                )
            }
            return trackRecord
        }
        record.markers = sequence.markers.enumerated().map { markerIndex, marker in
            MarkerRecord(
                id: marker.id,
                sortIndex: markerIndex,
                name: marker.name,
                timeValue: marker.time.value,
                timeTimescale: marker.time.timescale
            )
        }
        return record
    }
}

// MARK: - Record → Domain

extension ProjectRecord {
    /// 내용이 저장되기 전에 만든 프로젝트(시퀀스 레코드 없음)는 빈 시퀀스 하나로 연다.
    func makeProject() -> Project {
        let sortedSequences = sequences.sorted { $0.sortIndex < $1.sortIndex }.map { $0.makeSequence() }
        guard let project = Project(
            id: id,
            name: name,
            assets: assets.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.makeAsset() },
            folders: folders.sorted { $0.sortIndex < $1.sortIndex }.map {
                MediaFolder(id: $0.id, name: $0.name, assetIDs: $0.assetIDs)
            },
            sequences: sortedSequences
        ) else {
            return Project.makeNew(id: id, name: name)
        }
        return project
    }
}

private extension MediaAssetRecord {
    func makeAsset() -> MediaAsset? {
        let storedKind = kindRawValue
        guard let kind = MediaKind(rawValue: storedKind) else {
            Logger.project.error("알 수 없는 원본 종류라 건너뜀: \(storedKind, privacy: .public)")
            return nil
        }
        return MediaAsset(
            id: id,
            name: name,
            sourceURL: sourceURL,
            kind: kind,
            duration: CMTime(value: durationValue, timescale: durationTimescale)
        )
    }
}

private extension SequenceRecord {
    func makeSequence() -> EditSequence {
        EditSequence(
            id: id,
            name: name,
            tracks: tracks.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.makeTrack() },
            markers: markers.sorted { $0.sortIndex < $1.sortIndex }.map {
                Marker(id: $0.id, time: CMTime(value: $0.timeValue, timescale: $0.timeTimescale), name: $0.name)
            }
        )
    }
}

private extension TrackRecord {
    func makeTrack() -> Track? {
        let storedKind = kindRawValue
        guard let kind = TrackKind(rawValue: storedKind) else {
            Logger.project.error("알 수 없는 트랙 종류라 건너뜀: \(storedKind, privacy: .public)")
            return nil
        }
        return Track(id: id, kind: kind, clips: clips.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.makeClip() })
    }
}

private extension ClipRecord {
    func makeClip() -> Clip? {
        let sourceRange = CMTimeRange(
            start: CMTime(value: sourceStartValue, timescale: sourceStartTimescale),
            duration: CMTime(value: sourceDurationValue, timescale: sourceDurationTimescale)
        )
        let clip = Clip(
            id: id,
            assetID: assetID,
            sourceRange: sourceRange,
            timelineStart: CMTime(value: timelineStartValue, timescale: timelineStartTimescale)
        )
        if clip == nil {
            let clipID = id
            Logger.project.error("Clip 불변식을 어기는 저장값이라 건너뜀: \(clipID, privacy: .public)")
        }
        return clip
    }
}
