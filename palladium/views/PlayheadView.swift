import SwiftUI

struct PlayheadView: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2)
            .overlay(alignment: .top) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("재생 헤드")
    }
}
