import SwiftUI

/// 재생 헤드 세로선. 누르지 않고 아래 클립 끌기·트림을 통과시킨다. 잡는 머리는 눈금자(`TimelineRulerView`)에 있다(#79).
struct PlayheadView: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2)
            .accessibilityHidden(true)
    }
}
