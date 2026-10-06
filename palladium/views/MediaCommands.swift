import AppKit
import SwiftUI

extension FocusedValues {
    /// 미디어 패널 목록에 포커스가 있고 원본을 골랐을 때만 값이 있다.
    @Entry var renameSelectedAsset: (() -> Void)?
    /// 타임라인에서 클립을 하나 골랐을 때만 값이 있다(#78).
    @Entry var renameSelectedClip: (() -> Void)?
    /// 재생 헤드에서 나눌 클립이 있을 때만 값이 있다.
    @Entry var splitClips: (() -> Void)?
}

extension KeyEquivalent {
    static let f2 = KeyEquivalent(Character(UnicodeScalar(UInt32(NSF2FunctionKey))!))
}

struct MediaCommands: Commands {
    @FocusedValue(\.renameSelectedAsset) private var renameSelectedAsset
    @FocusedValue(\.renameSelectedClip) private var renameSelectedClip
    @FocusedValue(\.splitClips) private var splitClips

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            // 포커스가 미디어 패널에 있으면 원본 이름을, 아니면 타임라인에서 고른 클립의 별칭을 바꾼다.
            let rename = renameSelectedAsset ?? renameSelectedClip
            Button(ShortcutGuide.rename.title) {
                rename?()
            }
            // Windows 탐색기·포토샵처럼 F2로 바로 이름을 바꾼다.
            .keyboardShortcut(.f2, modifiers: [])
            .disabled(rename == nil)

            Button(ShortcutGuide.splitAtPlayhead.title) {
                splitClips?()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(splitClips == nil)
        }
    }
}
