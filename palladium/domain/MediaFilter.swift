import Foundation

/// 미디어 패널에서 원본을 거르는 조건. 모든 조건을 만족해야 일치한다.
nonisolated struct MediaFilter {
    /// 이름이나 태그의 일부. 비어 있거나 공백뿐이면 조건이 없다.
    var query = ""
    /// 비어 있으면 색상 레이블로 거르지 않는다.
    var colorLabels: Set<ColorLabel> = []

    func matches(_ asset: MediaAsset) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let matchesQuery = trimmedQuery.isEmpty
            || asset.name.localizedStandardContains(trimmedQuery)
            || asset.tags.contains { $0.localizedStandardContains(trimmedQuery) }
        let matchesColor = colorLabels.isEmpty || asset.colorLabel.map(colorLabels.contains) == true
        return matchesQuery && matchesColor
    }
}

nonisolated extension MediaFilter: Equatable {}
