/// パレットのキーバインド（UX-001 §4）。キー入力を、パレットの操作・編集操作・消費・素通しに振り分ける。
///
/// | キー | 扱い |
/// | --- | --- |
/// | ↑ / ↓、Ctrl+P / Ctrl+N | 選択を 1 行動かす（リピート可） |
/// | Enter（テンキーの Enter を含む） | 確定 |
/// | Cmd+Enter | 確定して「開く」まで押す |
/// | Tab | 選択候補のパスを検索語に展開 |
/// | Esc | パレットのみ閉じる |
/// | Cmd+X / C / V / A / Z、Cmd+Shift+Z | 検索フィールドの編集 |
///
/// - 注入中（ロック中）は文字入力も含めてすべて捨てる（DSN-001 §5）。
/// - IME の変換中はすべて IME に渡す。変換中の Enter / Esc / ↑↓ は確定・取消・候補選択に使われるため。
/// - Enter / Esc / Tab は、割り当てのない修飾の組み合わせやリピートでも検索フィールドに渡さず消費する。
///   渡すと編集終了（insertNewline:）・補完（complete:）・フォーカス移動（insertTab:）が起きるため。
/// - それ以外の割り当てのないキーは、文字入力やカーソル移動として検索フィールドに渡す。
///
/// 特殊キーは仮想キーコード（`VirtualKey`）で判定する。
public enum PaletteKeyBinding {
    /// テンキーの Enter（Carbon の kVK_ANSI_KeypadEnter）。
    /// `VirtualKey` はホットキーに指定できるキーだけを持ち、テンキーの Enter を含まないためここで定義する
    static let keypadEnterKeyCode: UInt16 = 0x4C

    private static let previousRow = -1
    private static let nextRow = 1

    /// 文字キーのショートカット。キー配列によらず、入力される文字で判定する（fzf / Emacs と同じ指癖）
    private static let letterShortcuts: [LetterShortcut: PaletteKeyResolution] = [
        LetterShortcut(.control, "p"): .perform(.moveSelection(by: previousRow)),
        LetterShortcut(.control, "n"): .perform(.moveSelection(by: nextRow)),
        LetterShortcut(.command, "x"): .edit(.cut),
        LetterShortcut(.command, "c"): .edit(.copy),
        LetterShortcut(.command, "v"): .edit(.paste),
        LetterShortcut(.command, "a"): .edit(.selectAll),
        LetterShortcut(.command, "z"): .edit(.undo),
        LetterShortcut([.command, .shift], "z"): .edit(.redo),
    ]

    public static func resolve(_ input: PaletteKeyInput) -> PaletteKeyResolution {
        // IME にも渡さないよう、変換中の判定より先に見る
        if input.isLocked { return .discard }
        if input.hasMarkedText { return .passThrough }
        if let resolution = resolveSpecialKey(input) {
            return resolution
        }
        return shortcutLetter(of: input)
            .flatMap { letterShortcuts[LetterShortcut(input.modifiers, $0)] } ?? .passThrough
    }

    /// 特殊キーの扱い。特殊キー以外は nil を返し、入力文字での判定に回す。
    private static func resolveSpecialKey(_ input: PaletteKeyInput) -> PaletteKeyResolution? {
        if input.keyCode == keypadEnterKeyCode {
            return consumingOneShot(input, action: confirmAction(for: input.modifiers))
        }
        let hasNoModifiers = input.modifiers.isEmpty
        switch VirtualKey(keyCode: input.keyCode) {
        case .return:
            return consumingOneShot(input, action: confirmAction(for: input.modifiers))
        case .escape:
            return consumingOneShot(input, action: hasNoModifiers ? .dismiss : nil)
        case .tab:
            return consumingOneShot(input, action: hasNoModifiers ? .expandSelection : nil)
        case .upArrow:
            return hasNoModifiers ? .perform(.moveSelection(by: previousRow)) : .passThrough
        case .downArrow:
            return hasNoModifiers ? .perform(.moveSelection(by: nextRow)) : .passThrough
        default:
            return nil
        }
    }

    private static func confirmAction(for modifiers: PaletteKeyModifiers) -> PaletteAction? {
        switch modifiers {
        case []: .confirm(openImmediately: false)
        case .command: .confirm(openImmediately: true)
        default: nil
        }
    }

    /// 1 回だけ実行するキー。押しっぱなしで確定や展開を繰り返さないよう、リピートは消費だけする
    private static func consumingOneShot(_ input: PaletteKeyInput, action: PaletteAction?) -> PaletteKeyResolution {
        guard let action, !input.isRepeat else { return .discard }
        return .perform(action)
    }

    /// ショートカットの判定に使う文字（小文字）。
    ///
    /// 入力文字が ASCII ならその文字で判定する（Dvorak 等でも表示どおりのキーで効く）。
    /// ASCII の記号は位置で読み替えない（Dvorak の Z の位置の ";" を Cmd+Z にしない）。
    /// ラテン文字を入力しない配列（キリル文字等）や文字が取れないキーでは、US 配列の位置で判定する。
    private static func shortcutLetter(of input: PaletteKeyInput) -> Character? {
        let characters = input.charactersIgnoringModifiers
        if characters.count == 1, let character = characters.first, character.isASCII {
            return character.isLetter ? Character(character.lowercased()) : nil
        }
        return VirtualKey(keyCode: input.keyCode)?.ansiLetter
    }
}

/// 修飾キーと文字の組。
private struct LetterShortcut: Hashable {
    let modifiers: PaletteKeyModifiers
    let letter: Character

    init(_ modifiers: PaletteKeyModifiers, _ letter: Character) {
        self.modifiers = modifiers
        self.letter = letter
    }
}

private extension VirtualKey {
    /// `NSEvent.keyCode`（UInt16）から引く。
    init?(keyCode: UInt16) {
        self.init(rawValue: UInt32(keyCode))
    }

    /// 文字キーの US 配列での文字（小文字）。文字キーの設定上の名前はその文字 1 字であることを使う
    var ansiLetter: Character? {
        let name = canonicalName
        guard name.count == 1, let letter = name.first, letter.isLetter else { return nil }
        return letter
    }
}
