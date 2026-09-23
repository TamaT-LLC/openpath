/// グローバルホットキー（パレットの再表示に使う）。Mac 層で Carbon の `RegisterEventHotKey` に渡す想定。
public struct Hotkey: Sendable, Hashable {
    /// macOS の仮想キーコード（Carbon の `kVK_*` と同じ値）
    public let keyCode: UInt32
    public let modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(key: VirtualKey, modifiers: HotkeyModifiers) {
        self.init(keyCode: key.rawValue, modifiers: modifiers)
    }
}

/// ホットキーの修飾キー。
///
/// `rawValue` のビット配置は Carbon の EventModifiers（`controlKey` / `shiftKey` / `optionKey` / `cmdKey`）と同じにし、
/// Mac 層が変換せずに `RegisterEventHotKey` へ渡せるようにする。
public struct HotkeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Carbon の `cmdKeyBit`
    private static let commandBit: UInt32 = 8
    /// Carbon の `shiftKeyBit`
    private static let shiftBit: UInt32 = 9
    /// Carbon の `optionKeyBit`
    private static let optionBit: UInt32 = 11
    /// Carbon の `controlKeyBit`
    private static let controlBit: UInt32 = 12

    public static let command = HotkeyModifiers(rawValue: 1 << commandBit)
    public static let shift = HotkeyModifiers(rawValue: 1 << shiftBit)
    public static let option = HotkeyModifiers(rawValue: 1 << optionBit)
    public static let control = HotkeyModifiers(rawValue: 1 << controlBit)
}

extension HotkeyModifiers {
    /// 表記に使う順序と名前。macOS のメニュー表記（⌃⌥⇧⌘）と同じ順に並べる
    static let canonicalOrder: [(modifier: HotkeyModifiers, name: String)] = [
        (.control, "ctrl"),
        (.option, "opt"),
        (.shift, "shift"),
        (.command, "cmd"),
    ]
}

extension Hotkey: CustomStringConvertible {
    /// 設定ファイルに書ける正規の表記（例: `ctrl+shift+o`）
    public var description: String {
        let modifierNames = HotkeyModifiers.canonicalOrder
            .filter { modifiers.contains($0.modifier) }
            .map(\.name)
        return (modifierNames + [keyName]).joined(separator: HotkeyParser.separator)
    }

    private var keyName: String {
        guard let key = VirtualKey(rawValue: keyCode) else {
            return "keycode(0x\(String(keyCode, radix: 16, uppercase: true)))"
        }
        return key.canonicalName
    }
}
