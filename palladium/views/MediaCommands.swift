import AppKit
import SwiftUI

extension FocusedValues {
    /// 미디어 패널에서 원본을 골랐을 때만 값이 있다.
    @Entry var renameSelectedAsset: (() -> Void)?
}

struct MediaCommands: Commands {
    @FocusedValue(\.renameSelectedAsset) private var renameSelectedAsset

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("원본 이름 변경") {
                renameSelectedAsset?()
            }
            // Windows 탐색기·포토샵처럼 F2로 바로 이름을 바꾼다.
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!)), modifiers: [])
            .disabled(renameSelectedAsset == nil)
        }
    }
}
