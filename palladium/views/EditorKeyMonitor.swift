import AppKit

/// 텍스트를 입력하는 중이 아닐 때 편집 창의 단일 키 단축키(Space·←/→·Delete·Esc 등)를 받는다.
/// 수식키가 있는 단축키(⌘B 클립 분할 등)는 메뉴가 맡는다. ⌘A·⌘C·⌘X·⌘V는 입력란에서 글자 선택·복사로 쓰이므로 여기서 받는다.
/// 메뉴 단축키로 두면 검색창·이름 입력란에서 띄어쓰기·커서 이동·글자 지우기까지 가로채므로 키 입력을 직접 살핀다.
final class EditorKeyMonitor {
    enum Key {
        case playPause
        case previousFrame
        case nextFrame
        case deleteSelection
        case rippleDeleteSelection
        case selectAll
        case escape
        case addMarker
        case addSubtitle
        case toggleNarration
        /// 타임라인 복사·잘라내기·붙여넣기(#62). 입력란을 편집 중이면 글자 복사로 넘어간다.
        case copy
        case cut
        case paste
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
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (49, []): return .playPause
        case (123, []): return .previousFrame
        case (124, []): return .nextFrame
        // 51은 Delete(백스페이스), 117은 앞쪽 지우기(fn+Delete).
        case (51, []), (117, []): return .deleteSelection
        case (51, .shift), (117, .shift): return .rippleDeleteSelection
        case (0, .command): return .selectAll
        case (53, []): return .escape
        case (46, []): return .addMarker
        case (17, []): return .addSubtitle
        case (15, []): return .toggleNarration
        case (8, .command): return .copy
        case (7, .command): return .cut
        case (9, .command): return .paste
        default: return nil
        }
    }

    /// 입력란을 편집 중이면 창의 첫 응답자가 필드 편집기(`NSText`)다.
    private static func isEditingText(in window: NSWindow?) -> Bool {
        window?.firstResponder is NSText
    }
}
