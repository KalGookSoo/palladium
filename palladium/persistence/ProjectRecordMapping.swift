import CoreMedia
import Foundation
import OSLog
import SwiftData

/// 프로젝트 내용(원본·폴더·시퀀스)의 하위 레코드 묶음. 저장본(`ProjectRecord`)과 백업본(`ProjectBackupRecord`)이 같은 변환을 쓴다.
struct ProjectContentRecords {
    var assets: [MediaAssetRecord]
    var folders: [MediaFolderRecord]
    var sequences: [SequenceRecord]
}

// MARK: - Domain → Record

extension ProjectContentRecords {
    init(project: Project) {
        assets = project.assets.enumerated().map { index, asset in
            MediaAssetRecord(
                id: asset.id,
                sortIndex: index,
                name: asset.name,
                sourceURL: asset.sourceURL,
                kindRawValue: asset.kind.rawValue,
                durationValue: asset.duration.value,
                durationTimescale: asset.duration.timescale,
                bookmarkData: asset.bookmarkData,
                colorLabelRawValue: asset.colorLabel?.rawValue,
                tags: asset.tags
            )
        }
        folders = project.folders.enumerated().map { index, folder in
            MediaFolderRecord(id: folder.id, sortIndex: index, name: folder.name, assetIDs: folder.assetIDs)
        }
        sequences = project.sequences.enumerated().map { index, sequence in
            SequenceRecord.make(from: sequence, sortIndex: index)
        }
    }

    func delete(in modelContext: ModelContext) {
        assets.forEach(modelContext.delete)
        folders.forEach(modelContext.delete)
        sequences.forEach(modelContext.delete)
    }
}

extension ProjectRecord {
    /// 기존 하위 레코드를 지우고 도메인 프로젝트의 내용으로 다시 채운다.
    /// 무엇이 바뀌었는지 비교하는 대신 통째로 교체해, 빠뜨린 삭제·순서 변경이 남지 않게 한다.
    func replaceContent(with project: Project, modifiedAt: Date, in modelContext: ModelContext) {
        ProjectContentRecords(assets: assets, folders: folders, sequences: sequences).delete(in: modelContext)

        let content = ProjectContentRecords(project: project)
        name = project.name
        self.modifiedAt = modifiedAt
        assetCount = project.assets.count
        sequenceCount = project.sequences.count
        assets = content.assets
        folders = content.folders
        sequences = content.sequences
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
                    timelineStartTimescale: clip.timelineStart.timescale,
                    transform: clip.transform
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

extension ProjectContentRecords {
    /// 시퀀스 레코드가 없으면(내용이 저장되기 전에 만든 프로젝트) 빈 시퀀스 하나로 연다.
    func makeProject(id: Project.ID, name: String) -> Project {
        guard let project = Project(
            id: id,
            name: name,
            assets: assets.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.makeAsset() },
            folders: folders.sorted { $0.sortIndex < $1.sortIndex }.map {
                MediaFolder(id: $0.id, name: $0.name, assetIDs: $0.assetIDs)
            },
            sequences: sequences.sorted { $0.sortIndex < $1.sortIndex }.map { $0.makeSequence() }
        ) else {
            return Project.makeNew(id: id, name: name)
        }
        return project
    }
}

extension ProjectRecord {
    func makeProject() -> Project {
        ProjectContentRecords(assets: assets, folders: folders, sequences: sequences).makeProject(id: id, name: name)
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
            duration: CMTime(value: durationValue, timescale: durationTimescale),
            bookmarkData: bookmarkData,
            // 알 수 없는 색 값은 레이블 없음으로 연다.
            colorLabel: colorLabelRawValue.flatMap(ColorLabel.init(rawValue:)),
            tags: tags
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
        var clip = Clip(
            id: id,
            assetID: assetID,
            sourceRange: sourceRange,
            timelineStart: CMTime(value: timelineStartValue, timescale: timelineStartTimescale)
        )
        clip?.transform = ClipTransform(centerX: transformCenterX, centerY: transformCenterY, scale: transformScale, opacity: transformOpacity)
        if clip == nil {
            let clipID = id
            Logger.project.error("Clip 불변식을 어기는 저장값이라 건너뜀: \(clipID, privacy: .public)")
        }
        return clip
    }
}
