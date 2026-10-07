import AppKit
import SwiftUI

/// 누르면 버튼 바로 옆에 색 견본 팝오버가 뜨는 색 선택 칸. SwiftUI `ColorPicker`는 시스템 색 패널을 마지막 자리(화면 구석)에 띄워
/// 버튼과 멀어지므로, AppKit `NSColorWell`의 간단한 모양(`.minimal`)을 쓴다. 팝오버 안의 버튼으로 전체 색 패널도 열 수 있다.
struct PopoverColorWell: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.supportsAlpha = false
        well.color = NSColor(color)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.color = $color
        let current = NSColor(color)
        if well.color.usingColorSpace(.sRGB) != current.usingColorSpace(.sRGB) {
            well.color = current
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    final class Coordinator: NSObject {
        var color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ well: NSColorWell) {
            color.wrappedValue = Color(nsColor: well.color)
        }
    }
}
