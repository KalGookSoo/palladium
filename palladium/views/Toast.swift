import SwiftUI

/// 잠깐 보였다 사라지는 알림(#96). macOS에는 기본 토스트가 없어 오버레이로 만든다.
/// 같은 문구를 다시 띄워도 새 알림으로 쳐(ID가 다름) 사라지는 시간을 처음부터 다시 잰다.
struct ToastMessage: Equatable {
    let id = UUID()
    let text: String
}

extension View {
    /// 위쪽 가운데에 `message`를 1.5초 보여주고 비운다. 클릭은 가로막지 않는다.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    static let duration = Duration.seconds(1.5)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message.text, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 4, y: 1)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
            .task(id: message?.id) {
                guard message != nil else { return }
                try? await Task.sleep(for: Self.duration)
                if !Task.isCancelled {
                    message = nil
                }
            }
    }
}
