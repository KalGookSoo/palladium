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
            MediaFolderRecord(id: folder.id, sortIndex: index, name: folder.name, assetIDs: folder.assetIDs, parentID: folder.parentID)
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
                .withAnimation(of: clip)
                .withTitle(of: clip)
                .withFilters(of: clip)
                .withChromaKey(of: clip)
                .withAudioEffects(of: clip)
                .withGroup(of: clip)
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
                MediaFolder(id: $0.id, name: $0.name, assetIDs: $0.assetIDs, parentID: $0.parentID)
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
        excludedRangeValues = asset.excludedRanges.isEmpty ? nil : asset.excludedRanges.flatMap {
            [$0.start.value, Int64($0.start.timescale), $0.duration.value, Int64($0.duration.timescale)]
        }
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
            crop: ClipCrop(storedTop: cropTop, bottom: cropBottom, left: cropLeft, right: cropRight),
            excludedRanges: excludedRanges
        )
    }

    /// 저장된 뺀 구간들. 쓰는 구간(없으면 원본 전체) 안으로 정리하고, 값이 맞지 않는 구간은 버린다.
    var excludedRanges: [CMTimeRange] {
        guard let values = excludedRangeValues, values.count % 4 == 0 else { return [] }
        let ranges = stride(from: 0, to: values.count, by: 4).compactMap { index -> CMTimeRange? in
            guard let startScale = Int32(exactly: values[index + 1]), let durationScale = Int32(exactly: values[index + 3]), startScale > 0, durationScale > 0 else { return nil }
            return CMTimeRange(start: CMTime(value: values[index], timescale: startScale), duration: CMTime(value: values[index + 2], timescale: durationScale))
        }
        let bounds = usedRange ?? CMTimeRange(start: .zero, duration: CMTime(value: durationValue, timescale: durationTimescale))
        return RangeExclusion.normalized(ranges, within: bounds)
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
        clip?.transform = ClipTransform(
            centerX: transformCenterX, centerY: transformCenterY, scale: transformScale, opacity: transformOpacity, rotation: transformRotation ?? 0
        )
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
        clip?.animation = animationData.flatMap { try? JSONDecoder().decode(StoredClipAnimation.self, from: $0) }?.animation ?? ClipAnimation()
        clip?.title = titleData.flatMap { try? JSONDecoder().decode(StoredTitle.self, from: $0) }?.title
        clip?.filters = filtersData.flatMap { try? JSONDecoder().decode([StoredFilter].self, from: $0) }?.compactMap(\.filter) ?? []
        clip?.chromaKey = chromaKeyData.flatMap { try? JSONDecoder().decode(StoredChromaKey.self, from: $0) }?.chromaKey
        clip?.groupID = groupID
        clip?.audioEffects = audioEffectsData.flatMap { try? JSONDecoder().decode(StoredAudioEffects.self, from: $0) }?.effects ?? AudioEffects()
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

// MARK: - Keyframes (#67)

private extension ClipRecord {
    func withAnimation(of clip: Clip) -> ClipRecord {
        animationData = clip.animation.isEmpty ? nil : try? JSONEncoder().encode(StoredClipAnimation(clip.animation))
        return self
    }
}

/// 키프레임 저장 모양. 시각은 value/timescale로 나눠 둔다(`CMTime`은 Codable이 아니다). 알 수 없는 보간은 선형으로 연다.
private struct StoredClipAnimation: Codable {
    struct Time: Codable {
        let value: Int64
        let timescale: Int32

        init(_ time: CMTime) {
            value = time.value
            timescale = time.timescale
        }

        var time: CMTime {
            CMTime(value: value, timescale: max(timescale, 1))
        }
    }

    struct TransformKey: Codable {
        let time: Time
        let centerX: Double
        let centerY: Double
        let scale: Double
        let opacity: Double
        let rotation: Double
        let interpolation: String
    }

    struct VolumeKey: Codable {
        let time: Time
        let volume: Double
        let interpolation: String
    }

    let transform: [TransformKey]
    let volume: [VolumeKey]

    init(_ animation: ClipAnimation) {
        transform = animation.transform.map {
            TransformKey(
                time: Time($0.time), centerX: $0.value.centerX, centerY: $0.value.centerY, scale: $0.value.scale,
                opacity: $0.value.opacity, rotation: $0.value.rotation, interpolation: $0.interpolation.rawValue
            )
        }
        volume = animation.volume.map { VolumeKey(time: Time($0.time), volume: $0.value, interpolation: $0.interpolation.rawValue) }
    }

    var animation: ClipAnimation {
        ClipAnimation(
            transform: transform.map {
                Keyframe(
                    time: $0.time.time,
                    value: ClipTransform(centerX: $0.centerX, centerY: $0.centerY, scale: $0.scale, opacity: $0.opacity, rotation: $0.rotation),
                    interpolation: KeyframeInterpolation(rawValue: $0.interpolation) ?? .linear
                )
            }.sorted { $0.time < $1.time },
            volume: volume.map {
                Keyframe(time: $0.time.time, value: $0.volume, interpolation: KeyframeInterpolation(rawValue: $0.interpolation) ?? .linear)
            }.sorted { $0.time < $1.time }
        )
    }
}

// MARK: - Title (#76)

private extension ClipRecord {
    func withTitle(of clip: Clip) -> ClipRecord {
        titleData = clip.title.flatMap { try? JSONEncoder().encode(StoredTitle($0)) }
        return self
    }
}

/// 타이틀 저장 모양. 색은 RGB 세 값으로 둔다.
private struct StoredTitle: Codable {
    struct RGB: Codable {
        let red: Double
        let green: Double
        let blue: Double

        init(_ color: SubtitleRGB) {
            red = color.red
            green = color.green
            blue = color.blue
        }

        var color: SubtitleRGB {
            SubtitleRGB(red: red, green: green, blue: blue)
        }
    }

    let text: String
    let fontName: String
    let fontSize: Double
    let textColor: RGB
    let outlineWidth: Double
    let outlineColor: RGB
    let hasShadow: Bool
    let backgroundColor: RGB
    let backgroundOpacity: Double

    init(_ title: TitleText) {
        text = title.text
        fontName = title.fontName
        fontSize = title.fontSize
        textColor = RGB(title.textColor)
        outlineWidth = title.outlineWidth
        outlineColor = RGB(title.outlineColor)
        hasShadow = title.hasShadow
        backgroundColor = RGB(title.backgroundColor)
        backgroundOpacity = title.backgroundOpacity
    }

    var title: TitleText {
        var title = TitleText(
            text: text, fontName: fontName, fontSize: fontSize, textColor: textColor.color, outlineWidth: outlineWidth,
            outlineColor: outlineColor.color, hasShadow: hasShadow, backgroundColor: backgroundColor.color, backgroundOpacity: backgroundOpacity
        )
        title.clamp()
        return title
    }
}

// MARK: - Filters (#68)

private extension ClipRecord {
    func withFilters(of clip: Clip) -> ClipRecord {
        filtersData = clip.filters.isEmpty ? nil : try? JSONEncoder().encode(clip.filters.map(StoredFilter.init))
        return self
    }
}

/// 필터 저장 모양. 알 수 없는 종류는 버린다.
private struct StoredFilter: Codable {
    let id: UUID
    let kind: String
    let intensity: Double

    init(_ filter: VideoFilter) {
        id = filter.id
        kind = filter.kind.rawValue
        intensity = filter.intensity
    }

    var filter: VideoFilter? {
        guard let kind = VideoFilterKind(rawValue: kind) else { return nil }
        var filter = VideoFilter(id: id, kind: kind, intensity: intensity)
        filter.clamp()
        return filter
    }
}

// MARK: - Chroma key (#70)

private extension ClipRecord {
    func withChromaKey(of clip: Clip) -> ClipRecord {
        chromaKeyData = clip.chromaKey.flatMap { try? JSONEncoder().encode(StoredChromaKey($0)) }
        return self
    }
}

private struct StoredChromaKey: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let tolerance: Double
    let softness: Double
    let spillSuppression: Double

    init(_ key: ChromaKey) {
        red = key.keyColor.red
        green = key.keyColor.green
        blue = key.keyColor.blue
        tolerance = key.tolerance
        softness = key.softness
        spillSuppression = key.spillSuppression
    }

    var chromaKey: ChromaKey {
        var key = ChromaKey(
            keyColor: SubtitleRGB(red: red, green: green, blue: blue), tolerance: tolerance, softness: softness, spillSuppression: spillSuppression
        )
        key.clamp()
        return key
    }
}

// MARK: - Audio effects (#74)

private extension ClipRecord {
    func withAudioEffects(of clip: Clip) -> ClipRecord {
        audioEffectsData = clip.audioEffects.isDefault ? nil : try? JSONEncoder().encode(StoredAudioEffects(clip.audioEffects))
        return self
    }
}

private struct StoredAudioEffects: Codable {
    let lowGain: Double
    let midGain: Double
    let highGain: Double
    let cutsLowRumble: Bool
    let reverb: Double
    let noiseGate: Double
    let gain: Double

    init(_ effects: AudioEffects) {
        lowGain = effects.lowGain
        midGain = effects.midGain
        highGain = effects.highGain
        cutsLowRumble = effects.cutsLowRumble
        reverb = effects.reverb
        noiseGate = effects.noiseGate
        gain = effects.gain
    }

    var effects: AudioEffects {
        var effects = AudioEffects(
            lowGain: lowGain, midGain: midGain, highGain: highGain, cutsLowRumble: cutsLowRumble, reverb: reverb, noiseGate: noiseGate, gain: gain
        )
        effects.clamp()
        return effects
    }
}

// MARK: - Group (#100)

private extension ClipRecord {
    func withGroup(of clip: Clip) -> ClipRecord {
        groupID = clip.groupID
        return self
    }
}
