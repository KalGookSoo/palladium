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
            .withTrim(of: asset)
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
            trackRecord.volume = track.volume
            trackRecord.isMuted = track.isMuted
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
                .withAudio(volume: clip.volume, isMuted: clip.isMuted)
                .withTransitions(of: clip)
                .withLabels(of: clip)
                .withColorAdjustment(of: clip)
                .withCrop(of: clip)
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
        record.subtitles = sequence.subtitles.enumerated().map { SubtitleRecord(subtitle: $1, sortIndex: $0) }
        record.masks = sequence.masks.enumerated().map { MaskRecord(mask: $1, sortIndex: $0) }
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
    func withTrim(of asset: MediaAsset) -> MediaAssetRecord {
        usedStartValue = asset.usedRange?.start.value
        usedStartTimescale = asset.usedRange?.start.timescale ?? standardTimescale
        usedDurationValue = asset.usedRange?.duration.value ?? 0
        usedDurationTimescale = asset.usedRange?.duration.timescale ?? standardTimescale
        sourceAssetID = asset.sourceAssetID
        (cropTop, cropBottom, cropLeft, cropRight) = asset.crop.storedValues
        return self
    }

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
            tags: tags,
            usedRange: usedRange,
            sourceAssetID: sourceAssetID,
            crop: ClipCrop(storedTop: cropTop, bottom: cropBottom, left: cropLeft, right: cropRight)
        )
    }

    /// 저장된 사용 구간. 길이가 0 이하이거나 원본 범위를 벗어나면 구간 없음(원본 전체)으로 연다.
    var usedRange: CMTimeRange? {
        guard let usedStartValue else { return nil }
        let range = CMTimeRange(
            start: CMTime(value: usedStartValue, timescale: usedStartTimescale),
            duration: CMTime(value: usedDurationValue, timescale: usedDurationTimescale)
        )
        let duration = CMTime(value: durationValue, timescale: durationTimescale)
        guard range.start >= .zero, range.duration > .zero, range.end <= duration else { return nil }
        return range
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
            },
            subtitles: subtitles.sorted { $0.sortIndex < $1.sortIndex }.map { $0.makeSubtitle() },
            masks: masks.sorted { $0.sortIndex < $1.sortIndex }.map { $0.makeMask() }
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
        var track = Track(id: id, kind: kind, clips: clips.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.makeClip() })
        track.volume = volume
        track.isMuted = isMuted
        return track
    }
}

private extension ClipRecord {
    func withAudio(volume: Double, isMuted: Bool) -> ClipRecord {
        self.volume = volume
        self.isMuted = isMuted
        return self
    }

    func withTransitions(of clip: Clip) -> ClipRecord {
        transitionKindRawValue = clip.transitionIn?.kind.rawValue
        transitionDurationValue = clip.transitionIn?.duration.value ?? 0
        transitionDurationTimescale = clip.transitionIn?.duration.timescale ?? standardTimescale
        audioCrossfadeValue = clip.audioCrossfadeIn?.value
        audioCrossfadeTimescale = clip.audioCrossfadeIn?.timescale ?? standardTimescale
        speed = clip.speed
        return self
    }

    func withLabels(of clip: Clip) -> ClipRecord {
        name = clip.name
        colorLabelRawValue = clip.colorLabel?.rawValue
        return self
    }

    func withColorAdjustment(of clip: Clip) -> ClipRecord {
        brightness = clip.colorAdjustment.brightness
        contrast = clip.colorAdjustment.contrast
        saturation = clip.colorAdjustment.saturation
        return self
    }

    func withCrop(of clip: Clip) -> ClipRecord {
        (cropTop, cropBottom, cropLeft, cropRight) = clip.crop.storedValues
        return self
    }

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
        clip?.volume = volume
        clip?.isMuted = isMuted
        if let kind = transitionKindRawValue.flatMap(TransitionKind.init(rawValue:)) {
            clip?.transitionIn = ClipTransition(kind: kind, duration: CMTime(value: transitionDurationValue, timescale: transitionDurationTimescale))
        }
        clip?.audioCrossfadeIn = audioCrossfadeValue.map { CMTime(value: $0, timescale: audioCrossfadeTimescale) }
        clip?.speed = Clip.speedOptions.contains(speed) ? speed : 1
        clip?.name = name
        clip?.colorLabel = colorLabelRawValue.flatMap(ColorLabel.init(rawValue:))
        var adjustment = ColorAdjustment(brightness: brightness, contrast: contrast, saturation: saturation)
        adjustment.clamp()
        clip?.colorAdjustment = adjustment
        clip?.crop = ClipCrop(storedTop: cropTop, bottom: cropBottom, left: cropLeft, right: cropRight)
        if clip == nil {
            let clipID = id
            Logger.project.error("Clip 불변식을 어기는 저장값이라 건너뜀: \(clipID, privacy: .public)")
        }
        return clip
    }
}

private extension ClipCrop {
    /// 저장할 값. 자르지 않았으면 모두 `nil`로 둔다.
    var storedValues: (Double?, Double?, Double?, Double?) {
        isDefault ? (nil, nil, nil, nil) : (top, bottom, left, right)
    }

    /// 저장된 값으로 만든 크롭. 없는 값은 0이고, 범위를 벗어난 값은 범위로 맞춘다.
    init(storedTop top: Double?, bottom: Double?, left: Double?, right: Double?) {
        self.init(top: top ?? 0, bottom: bottom ?? 0, left: left ?? 0, right: right ?? 0)
        clamp()
    }
}
