import AppKit

/// 텍스트를 입력하는 중이 아닐 때 Space(재생/일시정지)와 ←/→(이전·다음 프레임)를 받는다.
/// 메뉴 단축키로 두면 검색창·이름 입력란에서 띄어쓰기와 커서 이동까지 가로채므로 키 입력을 직접 살핀다.
final class PlaybackKeyMonitor {
    enum Key {
        case playPause
        case previousFrame
        case nextFrame
    }

    /// 편집 창이 여러 개 열려 있어도 앞에 있는 창 하나만 반응하도록, 창이 앞에 있을 때만 받는다.
    var isWindowActive = false
    private var monitor: Any?

    /// `handler`가 `true`를 돌려주면 키 입력을 소비하고, `false`면 원래대로 전달한다.
    func start(handler: @escaping (Key) -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isWindowActive, let key = Self.key(for: event), !Self.isEditingText(in: event.window) else {
                return event
            }
            return handler(key) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func key(for event: NSEvent) -> Key? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 49: return .playPause
        case 123: return .previousFrame
        case 124: return .nextFrame
        default: return nil
        }
    }

    /// 입력란을 편집 중이면 창의 첫 응답자가 필드 편집기(`NSText`)다.
    private static func isEditingText(in window: NSWindow?) -> Bool {
        window?.firstResponder is NSText
    }
}
