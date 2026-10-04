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
        bookmarkData: Data?
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.name = name
        self.sourceURL = sourceURL
        self.kindRawValue = kindRawValue
        self.durationValue = durationValue
        self.durationTimescale = durationTimescale
        self.bookmarkData = bookmarkData
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
        timelineStartTimescale: Int32
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
