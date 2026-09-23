import Carbon.HIToolbox
import Testing

import OpenPathCore

/// テスト用の 1 打鍵。実際の NSEvent と同じく、特殊キーにも charactersIgnoringModifiers の値を持たせる。
/// キーコードは Carbon の kVK_* を使い、Core 側の定数とは独立に実機の値で検証する。
struct KeyStroke: Sendable, CustomTestStringConvertible {
    let name: String
    let keyCode: UInt16
    let characters: String

    var testDescription: String { name }

    func input(
        _ modifiers: PaletteKeyModifiers = [],
        isRepeat: Bool = false,
        hasMarkedText: Bool = false,
        isLocked: Bool = false
    ) -> PaletteKeyInput {
        PaletteKeyInput(
            keyCode: keyCode,
            charactersIgnoringModifiers: characters,
            modifiers: modifiers,
            isRepeat: isRepeat,
            hasMarkedText: hasMarkedText,
            isLocked: isLocked
        )
    }

    /// 別の文字を出すキー配列（Dvorak・ロシア語など）で同じ物理キーを押した場合
    func typing(_ characters: String) -> KeyStroke {
        KeyStroke(name: "\(name)→\(characters)", keyCode: keyCode, characters: characters)
    }

    private init(name: String, keyCode: Int, characters: String) {
        self.init(name: name, keyCode: UInt16(keyCode), characters: characters)
    }

    private init(name: String, keyCode: UInt16, characters: String) {
        self.name = name
        self.keyCode = keyCode
        self.characters = characters
    }

    // 特殊キー（characters は NSEvent が返す値。矢印は NSUpArrowFunctionKey 等の私用領域の文字）
    static let returnKey = KeyStroke(name: "Return", keyCode: kVK_Return, characters: "\r")
    static let keypadEnter = KeyStroke(name: "テンキー Enter", keyCode: kVK_ANSI_KeypadEnter, characters: "\u{03}")
    static let escape = KeyStroke(name: "Esc", keyCode: kVK_Escape, characters: "\u{1B}")
    static let tab = KeyStroke(name: "Tab", keyCode: kVK_Tab, characters: "\t")
    static let upArrow = KeyStroke(name: "↑", keyCode: kVK_UpArrow, characters: "\u{F700}")
    static let downArrow = KeyStroke(name: "↓", keyCode: kVK_DownArrow, characters: "\u{F701}")
    static let leftArrow = KeyStroke(name: "←", keyCode: kVK_LeftArrow, characters: "\u{F702}")
    static let rightArrow = KeyStroke(name: "→", keyCode: kVK_RightArrow, characters: "\u{F703}")
    static let delete = KeyStroke(name: "Delete", keyCode: kVK_Delete, characters: "\u{7F}")
    static let space = KeyStroke(name: "Space", keyCode: kVK_Space, characters: " ")
    static let eisu = KeyStroke(name: "英数", keyCode: kVK_JIS_Eisu, characters: "")
    static let kana = KeyStroke(name: "かな", keyCode: kVK_JIS_Kana, characters: "")

    // 文字キー（US 配列）
    static let a = KeyStroke(name: "A", keyCode: kVK_ANSI_A, characters: "a")
    static let c = KeyStroke(name: "C", keyCode: kVK_ANSI_C, characters: "c")
    static let e = KeyStroke(name: "E", keyCode: kVK_ANSI_E, characters: "e")
    static let k = KeyStroke(name: "K", keyCode: kVK_ANSI_K, characters: "k")
    static let l = KeyStroke(name: "L", keyCode: kVK_ANSI_L, characters: "l")
    static let n = KeyStroke(name: "N", keyCode: kVK_ANSI_N, characters: "n")
    static let p = KeyStroke(name: "P", keyCode: kVK_ANSI_P, characters: "p")
    static let r = KeyStroke(name: "R", keyCode: kVK_ANSI_R, characters: "r")
    static let v = KeyStroke(name: "V", keyCode: kVK_ANSI_V, characters: "v")
    static let x = KeyStroke(name: "X", keyCode: kVK_ANSI_X, characters: "x")
    static let z = KeyStroke(name: "Z", keyCode: kVK_ANSI_Z, characters: "z")
    static let digit1 = KeyStroke(name: "1", keyCode: kVK_ANSI_1, characters: "1")
    static let slash = KeyStroke(name: "/", keyCode: kVK_ANSI_Slash, characters: "/")
}

/// キーと修飾キーの組（Cmd+Enter など）。
struct KeyChord: Sendable, CustomTestStringConvertible {
    let key: KeyStroke
    let modifiers: PaletteKeyModifiers

    init(_ key: KeyStroke, _ modifiers: PaletteKeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    var testDescription: String { "\(modifiers)\(key.name)" }

    func input(isRepeat: Bool = false, hasMarkedText: Bool = false, isLocked: Bool = false) -> PaletteKeyInput {
        key.input(modifiers, isRepeat: isRepeat, hasMarkedText: hasMarkedText, isLocked: isLocked)
    }

    /// パレットが自分の操作として扱うキー（UX-001 §4 と標準の編集ショートカット）
    static let paletteChords: [KeyChord] = [
        KeyChord(.returnKey),
        KeyChord(.returnKey, .command),
        KeyChord(.keypadEnter),
        KeyChord(.keypadEnter, .command),
        KeyChord(.escape),
        KeyChord(.tab),
        KeyChord(.upArrow),
        KeyChord(.downArrow),
        KeyChord(.p, .control),
        KeyChord(.n, .control),
        KeyChord(.x, .command),
        KeyChord(.c, .command),
        KeyChord(.v, .command),
        KeyChord(.a, .command),
        KeyChord(.z, .command),
        KeyChord(.z, [.command, .shift]),
    ]

    /// 検索フィールドへの文字入力・カーソル移動のキー
    static let textInputChords: [KeyChord] = [
        KeyChord(.a),
        KeyChord(.n),
        KeyChord(KeyStroke.a.typing("A"), .shift),
        KeyChord(.digit1),
        KeyChord(.slash),
        KeyChord(.space),
        KeyChord(.delete),
        KeyChord(.leftArrow),
        KeyChord(.rightArrow),
        KeyChord(.eisu),
        KeyChord(.kana),
    ]
}

extension PaletteKeyModifiers {
    static let singleModifiers: [PaletteKeyModifiers] = [.command, .control, .option, .shift]

    /// 4 つの修飾キーのすべての組み合わせ（修飾なしを含む 16 通り）
    static let allCombinations: [PaletteKeyModifiers] = singleModifiers.reduce([[]]) { combinations, modifier in
        combinations + combinations.map { $0.union(modifier) }
    }
}
