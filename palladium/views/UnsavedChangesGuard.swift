import AppKit
import SwiftUI

/// 닫기 확인 창의 문구. 첫 버튼은 저장(적용), 둘째는 버리기, 셋째는 취소다.
struct UnsavedChangesPrompt {
    var message: String
    var information = "저장하지 않으면 변경 사항이 사라집니다."
    var saveTitle = "저장"
    var discardTitle = "저장 안 함"

    /// 프로젝트 창(편집 창)의 저장 확인.
    static func project(named name: String) -> UnsavedChangesPrompt {
        UnsavedChangesPrompt(message: "\"\(name)\"의 변경 사항을 저장하시겠습니까?")
    }

    func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: saveTitle)
        alert.addButton(withTitle: discardTitle)
        alert.addButton(withTitle: "취소")
        return alert
    }
}

/// 저장(적용)하지 않은 변경이 있는 창을 닫거나 앱을 종료할 때 확인 창을 띄우고, 창 닫기 버튼에 변경 표시(점)를 단다.
/// 앱 전체가 같은 방식으로 묻는다: 프로젝트 창(저장하지 않은 프로젝트)과 클립 편집 창(적용하지 않은 트림·크롭, #85).
/// 프로젝트 창을 닫으면 딸린 클립 편집 창이 함께 닫히므로, 딸린 창에 적용하지 않은 변경이 있으면 그것부터 묻는다.
/// SwiftUI에는 창 닫기를 막는 방법이 없어, 창의 `NSWindowDelegate`를 감싸 `windowShouldClose(_:)`만 가로채고
/// 나머지 위임 호출은 SwiftUI가 설정한 원래 delegate로 넘긴다. 창이 살아 있는 동안 바뀌지 않는 뷰에 둔다(뷰가 사라지면 연결이 끊긴다).
struct UnsavedChangesGuard: NSViewRepresentable {
    /// 창과 프로젝트의 관계. 프로젝트 창을 닫거나 앱을 끌 때 딸린 창을 먼저 묻는 데 쓴다.
    enum Role {
        case project(Project.ID)
        case attached(to: Project.ID)
    }

    /// 지금 저장(적용)하지 않은 변경이 있는지. 닫는 순간의 값을 읽도록 클로저로 받는다.
    let hasUnsavedChanges: () -> Bool
    let prompt: UnsavedChangesPrompt
    let role: Role
    /// 저장(적용)에 성공하면 `true`. 실패하면 창을 닫거나 종료하지 않는다.
    let save: () -> Bool
    /// "저장 안 함"(버리기)을 고르면 호출된다.
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
        coordinator.prompt = prompt
        coordinator.role = role
        coordinator.save = save
        coordinator.discardChanges = discardChanges
        // 처음 그려질 때는 아직 창에 붙기 전이라 window가 nil일 수 있어 다음 런루프에서 연결한다.
        DispatchQueue.main.async {
            coordinator.attach(to: view.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var hasUnsavedChanges: () -> Bool = { false }
        var prompt = UnsavedChangesPrompt(message: "")
        var role = Role.project(UUID())
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
            window.isDocumentEdited = hasUnsavedChanges()
        }

        /// 열려 있고 저장(적용)하지 않은 변경이 있는지.
        var needsConfirmation: Bool {
            window?.isVisible == true && hasUnsavedChanges()
        }

        /// 이 창(프로젝트 창)에 딸린 창 중 확인이 필요한 것.
        var attachedNeedingConfirmation: [Coordinator] {
            guard case let .project(projectID) = role else { return [] }
            return UnsavedChangesRegistry.coordinators.allObjects.filter { other in
                guard case let .attached(ownerID) = other.role else { return false }
                return ownerID == projectID && other.needsConfirmation
            }
        }

        // MARK: - NSWindowDelegate

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // 함께 닫힐 딸린 창(클립 편집 창)에 적용하지 않은 변경이 있으면 그 창에서 먼저 묻고, 정해지면 다시 닫는다.
            if let attached = attachedNeedingConfirmation.first, let attachedWindow = attached.window {
                attachedWindow.makeKeyAndOrderFront(nil)
                attached.prompt.makeAlert().beginSheetModal(for: attachedWindow) { response in
                    guard attached.resolve(response) else { return }
                    attachedWindow.close()
                    // 적용한 변경이 프로젝트에 반영된 뒤 저장 여부를 묻도록 다음 런루프에서 다시 닫는다.
                    DispatchQueue.main.async { sender.performClose(nil) }
                }
                return false
            }
            guard hasUnsavedChanges() else {
                return originalDelegate?.windowShouldClose?(sender) ?? true
            }
            prompt.makeAlert().beginSheetModal(for: sender) { [weak self] response in
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

/// 앱을 종료할 때 저장(적용)하지 않은 변경이 있는 창을 찾기 위해 열린 창의 Coordinator를 약하게 모아 둔다.
enum UnsavedChangesRegistry {
    static let coordinators = NSHashTable<UnsavedChangesGuard.Coordinator>.weakObjects()
}

/// 앱을 종료하기 전에 저장(적용)하지 않은 변경이 있는 창마다 확인한다. 딸린 창(클립 편집 창)을 먼저 묻는다 — 적용하면 프로젝트가 바뀌어
/// 그다음 프로젝트 창이 저장을 묻는다. 하나라도 취소하거나 저장에 실패하면 종료하지 않는다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let coordinators = UnsavedChangesRegistry.coordinators.allObjects
        let attached = coordinators.filter {
            if case .attached = $0.role {
                true
            } else {
                false
            }
        }
        let projects = coordinators.filter {
            if case .project = $0.role {
                true
            } else {
                false
            }
        }
        for coordinator in attached + projects where coordinator.needsConfirmation {
            coordinator.window?.makeKeyAndOrderFront(nil)
            let response = coordinator.prompt.makeAlert().runModal()
            guard coordinator.resolve(response) else { return .terminateCancel }
        }
        return .terminateNow
    }
}
