import SwiftUI

extension ColorLabel {
    var title: String {
        switch self {
        case .red: "빨간색"
        case .orange: "주황색"
        case .yellow: "노란색"
        case .green: "초록색"
        case .blue: "파란색"
        case .purple: "보라색"
        case .gray: "회색"
        }
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
}
