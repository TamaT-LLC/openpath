import Foundation

/// `"ctrl+shift+o"` のようなホットキー文字列を `Hotkey` に変換する。
///
/// 要素は `+` で区切り、大文字小文字・並び順・要素前後の空白は区別しない。
/// 修飾キーは control（ctrl）/ shift / option（opt, alt）/ command（cmd）で、キーはちょうど 1 つ必要。
public enum HotkeyParser {
    static let separator = "+"

    private static let modifiersByName: [String: HotkeyModifiers] = [
        "ctrl": .control,
        "control": .control,
        "shift": .shift,
        "opt": .option,
        "option": .option,
        "alt": .option,
        "cmd": .command,
        "command": .command,
    ]

    public static func parse(_ source: String) throws(HotkeyParseError) -> Hotkey {
        let components = source
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if components == [""] {
            throw .empty
        }
        if components.contains(where: \.isEmpty) {
            throw .emptyComponent
        }

        var modifiers: HotkeyModifiers = []
        var parsedKey: (key: VirtualKey, name: String)?
        for component in components {
            let name = component.lowercased()
            if let modifier = modifiersByName[name] {
                guard !modifiers.contains(modifier) else { throw .duplicateModifier(component) }
                modifiers.insert(modifier)
            } else if let key = VirtualKey(name: name) {
                if let parsedKey { throw .multipleKeys(parsedKey.name, component) }
                parsedKey = (key, component)
            } else {
                throw .unknownKey(component)
            }
        }

        guard let parsedKey else { throw .missingKey }
        guard !modifiers.isEmpty else { throw .missingModifier }
        // shift だけのホットキーは大文字の入力そのものを奪ってしまう
        guard modifiers != .shift else { throw .shiftOnlyModifier }
        return Hotkey(key: parsedKey.key, modifiers: modifiers)
    }
}

/// ホットキー文字列のパースエラー。名前は設定ファイルに書かれたままの表記（前後の空白を除く）で持つ。
public enum HotkeyParseError: Error, Equatable, Sendable {
    /// 空文字列、または空白のみ
    case empty
    /// `ctrl++o` や `ctrl+` のように `+` で区切った要素が空
    case emptyComponent
    /// 修飾キーにもキーにも該当しない名前
    case unknownKey(String)
    /// 同じ修飾キーが 2 回以上ある（`ctrl+control` のような別名どうしを含む）
    case duplicateModifier(String)
    /// キーが 2 つ以上ある
    case multipleKeys(String, String)
    case missingKey
    case missingModifier
    /// 修飾キーが shift だけ
    case shiftOnlyModifier
}

extension HotkeyParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty: "ホットキーが空です"
        case .emptyComponent: "'+' の前後にキー名がありません"
        case .unknownKey(let name): "未知のキー名 '\(name)' です"
        case .duplicateModifier(let name): "修飾キー '\(name)' が重複しています"
        case .multipleKeys(let first, let second): "キーは 1 つだけ指定してください（'\(first)' と '\(second)'）"
        case .missingKey: "修飾キー以外のキーがありません"
        case .missingModifier: "修飾キー（ctrl / opt / cmd など）が必要です"
        case .shiftOnlyModifier: "shift 以外の修飾キー（ctrl / opt / cmd）が必要です"
        }
    }
}
