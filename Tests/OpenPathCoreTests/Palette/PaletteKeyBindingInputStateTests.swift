import Testing

import OpenPathCore

/// IME の変換中・注入中のロック・キーリピート・キー配列の違いによる振る舞い。
@Suite("PaletteKeyBinding: 入力状態")
struct PaletteKeyBindingInputStateTests {
    private static let allChords = KeyChord.paletteChords + KeyChord.textInputChords

    // MARK: - IME の変換中

    @Test("IME の変換中はパレットのキーもすべて IME に渡す（確定・取消・候補選択に使うため）", arguments: KeyChord.paletteChords)
    func paletteKeysGoToInputMethodWhileComposing(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input(hasMarkedText: true)) == .passThrough)
    }

    @Test("IME の変換中の文字入力もそのまま IME に渡す", arguments: KeyChord.textInputChords)
    func textInputGoesToInputMethodWhileComposing(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input(hasMarkedText: true)) == .passThrough)
    }

    @Test("IME の変換中は修飾付きの Enter / Esc / Tab も IME に渡す", arguments: PaletteKeyModifiers.allCombinations)
    func modifiedKeysGoToInputMethodWhileComposing(modifiers: PaletteKeyModifiers) {
        for key in [KeyStroke.returnKey, .keypadEnter, .escape, .tab] {
            #expect(PaletteKeyBinding.resolve(key.input(modifiers, hasMarkedText: true)) == .passThrough, "\(key.name)")
        }
    }

    // MARK: - ロック中（注入中）

    @Test("ロック中は文字入力を含むすべてのキーを捨てる", arguments: allChords)
    func everyKeyIsDiscardedWhileLocked(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input(isLocked: true)) == .discard)
    }

    @Test("ロック中は IME の変換中でも捨てる", arguments: allChords)
    func lockTakesPrecedenceOverComposition(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input(hasMarkedText: true, isLocked: true)) == .discard)
    }

    // MARK: - キーリピート

    @Test(
        "押しっぱなしのリピートでは確定・閉じる・展開を繰り返さず、消費だけする",
        arguments: [
            KeyChord(.returnKey),
            KeyChord(.returnKey, .command),
            KeyChord(.keypadEnter),
            KeyChord(.escape),
            KeyChord(.tab),
        ]
    )
    func repeatedOneShotKeysAreDiscarded(chord: KeyChord) {
        #expect(PaletteKeyBinding.resolve(chord.input(isRepeat: true)) == .discard)
    }

    @Test(
        "押しっぱなしのリピートで選択の移動は続ける",
        arguments: [
            (KeyChord(.upArrow), -1),
            (KeyChord(.downArrow), 1),
            (KeyChord(.p, .control), -1),
            (KeyChord(.n, .control), 1),
        ]
    )
    func repeatedMovesKeepMoving(chord: KeyChord, offset: Int) {
        #expect(PaletteKeyBinding.resolve(chord.input(isRepeat: true)) == .perform(.moveSelection(by: offset)))
    }

    @Test("押しっぱなしのリピートでも編集ショートカットは繰り返す")
    func repeatedEditCommandsRepeat() {
        #expect(PaletteKeyBinding.resolve(KeyStroke.v.input(.command, isRepeat: true)) == .edit(.paste))
    }

    // MARK: - キー配列

    @Test("Dvorak などでは物理位置ではなく入力される文字で Ctrl+N / P を判定する")
    func letterShortcutsFollowTypedCharacter() {
        // Dvorak では US 配列の L の位置で n、R の位置で p が入力される
        #expect(PaletteKeyBinding.resolve(KeyStroke.l.typing("n").input(.control)) == .perform(.moveSelection(by: 1)))
        #expect(PaletteKeyBinding.resolve(KeyStroke.r.typing("p").input(.control)) == .perform(.moveSelection(by: -1)))
        // US 配列の N / P の位置は Dvorak では b / l になるため、移動にしない
        #expect(PaletteKeyBinding.resolve(KeyStroke.n.typing("b").input(.control)) == .passThrough)
        #expect(PaletteKeyBinding.resolve(KeyStroke.p.typing("l").input(.control)) == .passThrough)
    }

    @Test("ラテン文字を入力しない配列（ロシア語など）では US 配列の位置で判定する")
    func letterShortcutsFallBackToKeyPositionForNonLatinLayouts() {
        #expect(PaletteKeyBinding.resolve(KeyStroke.n.typing("т").input(.control)) == .perform(.moveSelection(by: 1)))
        #expect(PaletteKeyBinding.resolve(KeyStroke.p.typing("з").input(.control)) == .perform(.moveSelection(by: -1)))
        #expect(PaletteKeyBinding.resolve(KeyStroke.v.typing("м").input(.command)) == .edit(.paste))
        #expect(PaletteKeyBinding.resolve(KeyStroke.a.typing("ф").input(.command)) == .edit(.selectAll))
        // 割り当てのない文字キーは位置で読み替えても素通し
        #expect(PaletteKeyBinding.resolve(KeyStroke.e.typing("у").input(.control)) == .passThrough)
    }

    @Test("文字キー以外の位置では読み替えない")
    func nonLetterKeysAreNotReinterpretedByPosition() {
        #expect(PaletteKeyBinding.resolve(KeyStroke.digit1.typing("¡").input(.command)) == .passThrough)
        #expect(PaletteKeyBinding.resolve(KeyStroke.eisu.input(.control)) == .passThrough)
    }

    @Test("文字が取れないキー（デッドキー等）は US 配列の位置で判定する")
    func letterShortcutsFallBackToKeyPositionWithoutCharacters() {
        #expect(PaletteKeyBinding.resolve(KeyStroke.n.typing("").input(.control)) == .perform(.moveSelection(by: 1)))
    }

    @Test("ラテン文字以外の ASCII 記号を入力するキーは位置で読み替えない")
    func asciiSymbolsAreNotReinterpretedByPosition() {
        // Dvorak では US 配列の Z の位置で ; が入力される。Cmd+; を Cmd+Z（取り消し）にしない
        #expect(PaletteKeyBinding.resolve(KeyStroke.z.typing(";").input(.command)) == .passThrough)
    }

    @Test("Shift で大文字になっても同じ文字として判定する")
    func uppercaseLettersMatchShortcuts() {
        #expect(PaletteKeyBinding.resolve(KeyStroke.z.typing("Z").input([.command, .shift])) == .edit(.redo))
        #expect(PaletteKeyBinding.resolve(KeyStroke.n.typing("N").input([.control, .shift])) == .passThrough)
    }
}
