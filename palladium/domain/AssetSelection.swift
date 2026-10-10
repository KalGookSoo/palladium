import Foundation

/// 미디어 패널에서 여러 원본을 고른 순서(#86). 타임라인에 이어 붙이거나 폴더로 옮길 때 이 순서를 쓴다.
nonisolated enum AssetSelectionOrder {
    /// 선택 묶음이 `selection`으로 바뀐 뒤의 순서. 빠진 원본은 지우고, 새로 더해진 원본은 뒤에 붙인다.
    /// ⌘ 클릭처럼 하나씩 더하면 고른 순서가 되고, ⇧ 클릭·⌘A처럼 한꺼번에 더해지면 목록에 보이는 순서(`listOrder`)로 붙인다.
    static func updated(_ previous: [MediaAsset.ID], selection: Set<MediaAsset.ID>, listOrder: [MediaAsset.ID]) -> [MediaAsset.ID] {
        let kept = previous.filter(selection.contains)
        let keptSet = Set(kept)
        let added = selection.subtracting(keptSet)
        let listed = listOrder.filter(added.contains)
        // 목록에 보이지 않는(검색·필터로 가려진) 원본도 잃지 않게 끝에 붙인다.
        let unlisted = added.subtracting(listed).sorted { $0.uuidString < $1.uuidString }
        return kept + listed + unlisted
    }

    /// `assetIDs`를 고른 순서대로 늘어놓는다. 순서를 모르는 원본은 목록 순서로 뒤에 둔다.
    static func ordered(_ assetIDs: Set<MediaAsset.ID>, by order: [MediaAsset.ID], listOrder: [MediaAsset.ID]) -> [MediaAsset.ID] {
        updated(order, selection: assetIDs, listOrder: listOrder)
    }
}

/// 미디어 패널에서 끄는 원본들을 글자로 담는다(#86). 원본 ID를 줄마다 하나씩 담아 순서를 지킨다.
/// 예전처럼 ID 하나만 담긴 글자도 그대로 읽는다.
nonisolated enum AssetDragPayload {
    static func encode(_ assetIDs: [MediaAsset.ID]) -> String {
        assetIDs.map(\.uuidString).joined(separator: "\n")
    }

    /// 원본 ID가 아닌 줄(파일 경로 등)은 건너뛴다.
    static func decode(_ text: String) -> [MediaAsset.ID] {
        text.split(whereSeparator: \.isNewline).compactMap { UUID(uuidString: String($0)) }
    }
}
