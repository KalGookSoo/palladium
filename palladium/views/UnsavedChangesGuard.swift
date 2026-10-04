import AppKit
import SwiftUI

/// 저장하지 않은 변경이 있는 편집 창을 닫거나 앱을 종료할 때 확인 창을 띄우고, 창 닫기 버튼에 변경 표시(점)를 단다.
/// SwiftUI에는 창 닫기를 막는 방법이 없어, 창의 `NSWindowDelegate`를 감싸 `windowShouldClose(_:)`만 가로채고
/// 나머지 위임 호출은 SwiftUI가 설정한 원래 delegate로 넘긴다.
struct UnsavedChangesGuard: NSViewRepresentable {
    let hasUnsavedChanges: Bool
    let projectName: String
    /// 저장에 성공하면 `true`. 실패하면 창을 닫거나 종료하지 않는다.
    let save: () -> Bool
    /// "저장 안 함"을 고르면 호출된다. 저장하지 않은 변경의 백업본을 지우는 데 쓴다.
    let discardChanges: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    /// 창을 찾는 데만 쓰므로 크기를 0으로 둔다. 창 전체를 덮으면 그 위에서 분할 뷰 경계의
    /// 크기 조절 커서가 나타나지 않고 경계를 끌 수도 없다.
    func sizeThatFits(_: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
        .zero
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hasUnsavedChanges = hasUnsavedChanges
        coordinator.projectName = projectName
        coordinator.save = save
        coordinator.discardChanges = discardChanges
        // 처음 그려질 때는 아직 창에 붙기 전이라 window가 nil일 수 있어 다음 런루프에서 연결한다.
        DispatchQueue.main.async {
            coordinator.attach(to: view.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var hasUnsavedChanges = false
        var projectName = ""
        var save: () -> Bool = { true }
        var discardChanges: () -> Void = {}
        private(set) weak var window: NSWindow?
        private weak var originalDelegate: NSWindowDelegate?

        override init() {
            super.init()
            UnsavedChangesRegistry.coordinators.add(self)
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window.delegate !== self {
                originalDelegate = window.delegate
                window.delegate = self
            }
            self.window = window
            window.isDocumentEdited = hasUnsavedChanges
        }

        // MARK: - NSWindowDelegate

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard hasUnsavedChanges else {
                return originalDelegate?.windowShouldClose?(sender) ?? true
            }
            makeUnsavedChangesAlert(projectName: projectName).beginSheetModal(for: sender) { [weak self] response in
                guard let self, resolve(response) else { return }
                sender.close()
            }
            return false
        }

        /// 확인 창의 응답을 처리하고, 창을 닫거나 종료를 계속해도 되면 `true`를 돌려준다.
        func resolve(_ response: NSApplication.ModalResponse) -> Bool {
            switch response {
            case .alertFirstButtonReturn:
                return save()
            case .alertSecondButtonReturn:
                discardChanges()
                return true
            default:
                return false
            }
        }

        // MARK: - Forwarding

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for _: Selector!) -> Any? {
            originalDelegate
        }
    }
}

/// 앱을 종료할 때 저장하지 않은 변경이 있는 편집 창을 찾기 위해 열린 창의 Coordinator를 약하게 모아 둔다.
enum UnsavedChangesRegistry {
    static let coordinators = NSHashTable<UnsavedChangesGuard.Coordinator>.weakObjects()
}

func makeUnsavedChangesAlert(projectName: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "\"\(projectName)\"의 변경 사항을 저장하시겠습니까?"
    alert.informativeText = "저장하지 않으면 변경 사항이 사라집니다."
    alert.addButton(withTitle: "저장")
    alert.addButton(withTitle: "저장 안 함")
    alert.addButton(withTitle: "취소")
    return alert
}

/// 앱을 종료하기 전에 저장하지 않은 변경이 있는 창마다 확인한다. 하나라도 취소하거나 저장에 실패하면 종료하지 않는다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let unsavedCoordinators = UnsavedChangesRegistry.coordinators.allObjects.filter {
            $0.hasUnsavedChanges && $0.window?.isVisible == true
        }
        for coordinator in unsavedCoordinators {
            coordinator.window?.makeKeyAndOrderFront(nil)
            let response = makeUnsavedChangesAlert(projectName: coordinator.projectName).runModal()
            guard coordinator.resolve(response) else { return .terminateCancel }
        }
        return .terminateNow
    }
}
