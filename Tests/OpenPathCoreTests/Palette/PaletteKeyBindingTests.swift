import Testing

import OpenPathCore

/// UX-001 §4 のキーバインド。修飾キーは 16 通りの組み合わせをすべて確かめる。
@Suite("PaletteKeyBinding: パレットのキー")
struct PaletteKeyBindingTests {
    private static let enterKeys: [KeyStroke] = [.returnKey, .keypadEnter]

    @Test("Enter は確定、Cmd+Enter は確定して開く。その他の修飾は何もせず消費する", arguments: enterKeys, PaletteKeyModifiers.allCombinations)
    func enter(key: KeyStroke, modifiers: PaletteKeyModifiers) {
        let expected: PaletteKeyResolution = switch modifiers {
        case []: .perform(.confirm(openImmediately: false))
        case .command: .perform(.confirm(openImmediately: true))
        // 検索フィールドに渡すと編集終了（insertNewline:）として扱われるため消費する
        default: .discard
        }

        #expect(PaletteKeyBinding.resolve(key.input(modifiers)) == expected)
    }

    @Test("Esc はパレットを閉じる。修飾付きは何もせず消費する", arguments: PaletteKeyModifiers.allCombinations)
    func escape(modifiers: PaletteKeyModifiers) {
        // 検索フィールドに渡すと補完候補（complete:）が開くため消費する
        let expected: PaletteKeyResolution = modifiers.isEmpty ? .perform(.dismiss) : .discard

        #expect(PaletteKeyBinding.resolve(KeyStroke.escape.input(modifiers)) == expected)
    }

    @Test("Tab は選択候補を検索語に展開する。修飾付きは何もせず消費する", arguments: PaletteKeyModifiers.allCombinations)
    func tab(modifiers: PaletteKeyModifiers) {
        // Shift+Tab 等を検索フィールドに渡すとフォーカスが外れるため消費する
        let expected: PaletteKeyResolution = modifiers.isEmpty ? .perform(.expandSelection) : .discard

        #expect(PaletteKeyBinding.resolve(KeyStroke.tab.input(modifiers)) == expected)
    }

    @Test("↑ / ↓ は選択を 1 行動かす。修飾付きは検索フィールドのカーソル操作に渡す", arguments: PaletteKeyModifiers.allCombinations)
    func arrows(modifiers: PaletteKeyModifiers) {
        let expectedUp: PaletteKeyResolution = modifiers.isEmpty ? .perform(.moveSelection(by: -1)) : .passThrough
        let expectedDown: PaletteKeyResolution = modifiers.isEmpty ? .perform(.moveSelection(by: 1)) : .passThrough

        #expect(PaletteKeyBinding.resolve(KeyStroke.upArrow.input(modifiers)) == expectedUp)
        #expect(PaletteKeyBinding.resolve(KeyStroke.downArrow.input(modifiers)) == expectedDown)
    }

    @Test("Ctrl+P / Ctrl+N は選択を 1 行動かす。その他の修飾は文字入力として渡す", arguments: PaletteKeyModifiers.allCombinations)
    func controlPN(modifiers: PaletteKeyModifiers) {
        let expectedP: PaletteKeyResolution = modifiers == .control ? .perform(.moveSelection(by: -1)) : .passThrough
        let expectedN: PaletteKeyResolution = modifiers == .control ? .perform(.moveSelection(by: 1)) : .passThrough

        #expect(PaletteKeyBinding.resolve(KeyStroke.p.input(modifiers)) == expectedP)
        #expect(PaletteKeyBinding.resolve(KeyStroke.n.input(modifiers)) == expectedN)
    }

    @Test(
        "Cmd+X / C / V / A / Z と Cmd+Shift+Z は検索フィールドの編集。その他の修飾は文字入力として渡す",
        arguments: [
            (KeyStroke.x, PaletteEditCommand.cut),
            (KeyStroke.c, .copy),
            (KeyStroke.v, .paste),
            (KeyStroke.a, .selectAll),
            (KeyStroke.z, .undo),
        ],
        PaletteKeyModifiers.allCombinations
    )
    func editCommands(shortcut: (key: KeyStroke, command: PaletteEditCommand), modifiers: PaletteKeyModifiers) {
        let isRedo = shortcut.command == .undo && modifiers == [.command, .shift]
        let expected: PaletteKeyResolution = switch modifiers {
        case .command: .edit(shortcut.command)
        case _ where isRedo: .edit(.redo)
        default: .passThrough
        }

        #expect(PaletteKeyBinding.resolve(shortcut.key.input(modifiers)) == expected)
    }

    @Test("文字入力・削除・左右のカーソル移動・英数 / かなキーは検索フィールドに渡す", arguments: KeyChord.textInputChords)
    func textInputPassesThrough(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input()) == .passThrough)
    }

    @Test(
        "Emacs 風のカーソル移動（Ctrl+A / E / K）は検索フィールドに渡す",
        arguments: [KeyStroke.a, .e, .k]
    )
    func emacsCursorKeysPassThrough(key: KeyStroke) {
        #expect(PaletteKeyBinding.resolve(key.input(.control)) == .passThrough)
    }
}
