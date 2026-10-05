import Foundation

nonisolated enum AspectRatioPreset: CaseIterable {
    case landscape16x9
    case portrait9x16
    case square1x1
}

// MARK: - Queries

nonisolated extension AspectRatioPreset {
    var widthRatio: Int {
        switch self {
        case .landscape16x9: 16
        case .portrait9x16: 9
        case .square1x1: 1
        }
    }

    var heightRatio: Int {
        switch self {
        case .landscape16x9: 9
        case .portrait9x16: 16
        case .square1x1: 1
        }
    }
}

nonisolated extension AspectRatioPreset: Identifiable {
    var id: Self {
        self
    }
}
