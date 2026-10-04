import AppKit
import SwiftUI

extension FocusedValues {
    /// 미디어 패널에서 원본을 골랐을 때만 값이 있다.
    @Entry var renameSelectedAsset: (() -> Void)?
    /// 재생 헤드에서 나눌 클립이 있을 때만 값이 있다.
    @Entry var splitClips: (() -> Void)?
}

extension KeyEquivalent {
    static let f2 = KeyEquivalent(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!))
}

struct MediaCommands: Commands {
    @FocusedValue(\.renameSelectedAsset) private var renameSelectedAsset
    @FocusedValue(\.splitClips) private var splitClips

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("원본 이름 변경") {
                renameSelectedAsset?()
            }
            // Windows 탐색기·포토샵처럼 F2로 바로 이름을 바꾼다.
            .keyboardShortcut(.f2, modifiers: [])
            .disabled(renameSelectedAsset == nil)

            Button(ShortcutGuide.splitAtPlayhead.title) {
                splitClips?()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(splitClips == nil)
        }
    }
}
