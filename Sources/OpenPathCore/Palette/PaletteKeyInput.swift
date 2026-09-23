/// キー入力時に押されていた修飾キー。
/// Caps Lock・テンキー・ファンクションキーのフラグ（矢印キーで立つ等）は判定に使わないため持たない。
public struct PaletteKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = PaletteKeyModifiers(rawValue: 1 << 0)
    public static let option = PaletteKeyModifiers(rawValue: 1 << 1)
    public static let shift = PaletteKeyModifiers(rawValue: 1 << 2)
    public static let command = PaletteKeyModifiers(rawValue: 1 << 3)
}

extension PaletteKeyModifiers: CustomStringConvertible {
    /// macOS のメニューと同じ ⌃⌥⇧⌘ の順の記号。修飾なしは空文字列
    public var description: String {
        let symbols: [(PaletteKeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { contains($0.0) }.map(\.1).joined()
    }
}

/// パレットが受け取った 1 回のキー入力（keyDown）と、その時点のパレットの状態。
///
/// AppKit の `NSEvent` を Core に持ち込まないよう、キーの判定に必要な値だけを持つ。
public struct PaletteKeyInput: Equatable, Sendable {
    /// 仮想キーコード（`NSEvent.keyCode`）。物理的なキーの位置を表す
    public let keyCode: UInt16
    /// 修飾キーを除いた入力文字（`NSEvent.charactersIgnoringModifiers`）。Shift だけは反映される
    public let charactersIgnoringModifiers: String
    public let modifiers: PaletteKeyModifiers
    /// キーの押しっぱなしによるリピートか
    public let isRepeat: Bool
    /// IME で変換中の未確定文字（markedText）が検索フィールドにあるか
    public let hasMarkedText: Bool
    /// 注入中でパレットがロックされているか（`PaletteViewModel.isLocked`）
    public let isLocked: Bool

    public init(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifiers: PaletteKeyModifiers = [],
        isRepeat: Bool = false,
        hasMarkedText: Bool = false,
        isLocked: Bool = false
    ) {
        self.keyCode = keyCode
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.hasMarkedText = hasMarkedText
        self.isLocked = isLocked
    }
}
