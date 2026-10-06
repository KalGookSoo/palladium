import CoreMedia
import Foundation
import SwiftData

// SwiftData 관계 배열은 저장 후 순서를 보장하지 않으므로 모든 하위 레코드에 `sortIndex`를 둔다.
// `CMTime`은 정밀도를 잃지 않도록 `value`/`timescale`로 나눠 저장한다. 도메인과 같은 `id`를 쓴다.
// 원본·폴더·시퀀스 레코드는 저장본(`project`)이나 백업본(`backup`) 중 한쪽에 속한다.

@Model
final class MediaAssetRecord {
    var id: UUID
    var sortIndex: Int
    var name: String
    var sourceURL: URL
    var kindRawValue: String
    var durationValue: Int64
    var durationTimescale: Int32
    var bookmarkData: Data?
    var colorLabelRawValue: String?
    // 기본값이 있어야 이 속성이 생기기 전에 저장한 레코드도 열린다.
    var tags: [String] = []
    var project: ProjectRecord?
    var backup: ProjectBackupRecord?

    init(
        id: UUID,
        sortIndex: Int,
        name: String,
        sourceURL: URL,
        kindRawValue: String,
        durationValue: Int64,
        durationTimescale: Int32,
        bookmarkData: Data?,
        colorLabelRawValue: String?,
        tags: [String]
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
        self.sourceURL = sourceURL
        self.kindRawValue = kindRawValue
        self.durationValue = durationValue
        self.durationTimescale = durationTimescale
        self.bookmarkData = bookmarkData
        self.colorLabelRawValue = colorLabelRawValue
        self.tags = tags
    }
}

@Model
final class MediaFolderRecord {
    var id: UUID
    var sortIndex: Int
    var name: String
    /// 폴더 안 원본 순서가 그대로 보존되도록 배열 값으로 저장한다.
    var assetIDs: [UUID]
    var project: ProjectRecord?
    var backup: ProjectBackupRecord?

    init(id: UUID, sortIndex: Int, name: String, assetIDs: [UUID]) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
        self.assetIDs = assetIDs
    }
}

@Model
final class SequenceRecord {
    var id: UUID
    var sortIndex: Int
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \TrackRecord.sequence) var tracks: [TrackRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \MarkerRecord.sequence) var markers: [MarkerRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \SubtitleRecord.sequence) var subtitles: [SubtitleRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \MaskRecord.sequence) var masks: [MaskRecord] = []
    var project: ProjectRecord?
    var backup: ProjectBackupRecord?

    init(id: UUID, sortIndex: Int, name: String) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
    }
}

@Model
final class TrackRecord {
    var id: UUID
    var sortIndex: Int
    var kindRawValue: String
    // 기본값이 있어야 이 속성이 생기기 전에 저장한 레코드도 열린다.
    var volume: Double = 1
    var isMuted = false
    @Relationship(deleteRule: .cascade, inverse: \ClipRecord.track) var clips: [ClipRecord] = []
    var sequence: SequenceRecord?

    init(id: UUID, sortIndex: Int, kindRawValue: String) {
        self.id = id
        self.sortIndex = sortIndex
        self.kindRawValue = kindRawValue
    }
}

@Model
final class ClipRecord {
    var id: UUID
    var sortIndex: Int
    var assetID: UUID
    var sourceStartValue: Int64
    var sourceStartTimescale: Int32
    var sourceDurationValue: Int64
    var sourceDurationTimescale: Int32
    var timelineStartValue: Int64
    var timelineStartTimescale: Int32
    // 기본값이 있어야 이 속성이 생기기 전에 저장한 레코드도 열린다.
    var transformCenterX: Double = 0.5
    var transformCenterY: Double = 0.5
    var transformScale: Double = 1
    var transformOpacity: Double = 1
    var volume: Double = 1
    var isMuted = false
    /// 전환 종류(`TransitionKind`). `nil`이면 전환이 없다.
    var transitionKindRawValue: String?
    var transitionDurationValue: Int64 = 0
    var transitionDurationTimescale: Int32 = 600
    /// 오디오 크로스페이드 길이. `nil`이면 없다.
    var audioCrossfadeValue: Int64?
    var audioCrossfadeTimescale: Int32 = 600
    var speed: Double = 1
    /// 클립 별칭(#78). `nil`이면 원본 이름을 보여준다.
    var name: String?
    /// 클립 색상 레이블(`ColorLabel`). `nil`이면 없다.
    var colorLabelRawValue: String?
    /// 기본 색보정(#61). 기본값은 원본 그대로다.
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var track: TrackRecord?

    init(
        id: UUID,
        sortIndex: Int,
        assetID: UUID,
        sourceStartValue: Int64,
        sourceStartTimescale: Int32,
        sourceDurationValue: Int64,
        sourceDurationTimescale: Int32,
        timelineStartValue: Int64,
        timelineStartTimescale: Int32,
        transform: ClipTransform
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.assetID = assetID
        self.sourceStartValue = sourceStartValue
        self.sourceStartTimescale = sourceStartTimescale
        self.sourceDurationValue = sourceDurationValue
        self.sourceDurationTimescale = sourceDurationTimescale
        self.timelineStartValue = timelineStartValue
        self.timelineStartTimescale = timelineStartTimescale
        transformCenterX = transform.centerX
        transformCenterY = transform.centerY
        transformScale = transform.scale
        transformOpacity = transform.opacity
    }
}

@Model
final class MarkerRecord {
    var id: UUID
    var sortIndex: Int
    var name: String
    var timeValue: Int64
    var timeTimescale: Int32
    var sequence: SequenceRecord?

    init(id: UUID, sortIndex: Int, name: String, timeValue: Int64, timeTimescale: Int32) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
        self.timeValue = timeValue
        self.timeTimescale = timeTimescale
    }
}

/// 자막 하나(#4). 기존 저장소가 가벼운 마이그레이션으로 열리도록 모든 속성에 기본값을 둔다.
@Model
final class SubtitleRecord {
    var id = UUID()
    var sortIndex = 0
    var text = ""
    var startValue: Int64 = 0
    var startTimescale: Int32 = 600
    var durationValue: Int64 = 0
    var durationTimescale: Int32 = 600
    var fontSize = 54.0
    var positionRawValue = "bottom"
    var colorRawValue = "white"
    var hasBackground = true
    var sequence: SequenceRecord?

    init(subtitle: Subtitle, sortIndex: Int) {
        id = subtitle.id
        self.sortIndex = sortIndex
        text = subtitle.text
        startValue = subtitle.range.start.value
        startTimescale = subtitle.range.start.timescale
        durationValue = subtitle.range.duration.value
        durationTimescale = subtitle.range.duration.timescale
        fontSize = subtitle.style.fontSize
        positionRawValue = subtitle.style.position.rawValue
        colorRawValue = subtitle.style.color.rawValue
        hasBackground = subtitle.style.hasBackground
    }

    func makeSubtitle() -> Subtitle {
        Subtitle(
            id: id,
            range: CMTimeRange(
                start: CMTime(value: startValue, timescale: startTimescale),
                duration: CMTime(value: durationValue, timescale: durationTimescale)
            ),
            text: text,
            style: SubtitleStyle(
                fontSize: fontSize,
                position: SubtitlePosition(rawValue: positionRawValue) ?? .bottom,
                color: SubtitleColor(rawValue: colorRawValue) ?? .white,
                hasBackground: hasBackground
            )
        )
    }
}

/// 마스크 하나(#59). 기존 저장소가 가벼운 마이그레이션으로 열리도록 모든 속성에 기본값을 둔다.
@Model
final class MaskRecord {
    var id = UUID()
    var sortIndex = 0
    var startValue: Int64 = 0
    var startTimescale: Int32 = 600
    var durationValue: Int64 = 0
    var durationTimescale: Int32 = 600
    var centerX = 0.5
    var centerY = 0.5
    var width = 0.3
    var height = 0.3
    var shapeRawValue = "rectangle"
    var effectRawValue = "blur"
    var strength = 0.5
    var sequence: SequenceRecord?

    init(mask: Mask, sortIndex: Int) {
        id = mask.id
        self.sortIndex = sortIndex
        startValue = mask.range.start.value
        startTimescale = mask.range.start.timescale
        durationValue = mask.range.duration.value
        durationTimescale = mask.range.duration.timescale
        centerX = mask.area.centerX
        centerY = mask.area.centerY
        width = mask.area.width
        height = mask.area.height
        shapeRawValue = mask.shape.rawValue
        effectRawValue = mask.effect.rawValue
        strength = mask.strength
    }

    func makeMask() -> Mask {
        Mask(
            id: id,
            range: CMTimeRange(
                start: CMTime(value: startValue, timescale: startTimescale),
                duration: CMTime(value: durationValue, timescale: durationTimescale)
            ),
            area: MaskArea(centerX: centerX, centerY: centerY, width: width, height: height),
            shape: MaskShape(rawValue: shapeRawValue) ?? .rectangle,
            effect: MaskEffect(rawValue: effectRawValue) ?? .blur,
            strength: strength
        )
    }
}
