/// config.toml のあるテーブルで使えるキーの集合。
/// `CaseIterable` から既知のキーを作ることで、デコード対象と未知キー判定の定義がずれないようにする
protocol ConfigKeySet: CaseIterable, RawRepresentable<String> {}

/// トップレベルのキー（DSN-002 §6）
enum TopLevelConfigKey: String, ConfigKeySet {
    case roots
    case depth
    case includeFiles = "include_files"
    case autoConfirm = "auto_confirm"
    case hotkey
    case disabledApps = "disabled_apps"
    case ignore
    case ghq
}

/// `[ghq]` テーブルのキー
enum GhqConfigKey: String, ConfigKeySet {
    case enabled
}

/// TOML のテーブルから型を確かめながら値を取り出す。キーが無ければ nil、型が違えばキーパス付きのエラー
struct ConfigTableReader<Key: ConfigKeySet> {
    private static var keyPathSeparator: String { "." }

    private let table: TOMLTable
    /// このテーブル自身のキーパス。ルートテーブルなら nil
    private let tablePath: String?

    init(table: TOMLTable, tablePath: String? = nil) {
        self.table = table
        self.tablePath = tablePath
    }

    func string(_ key: Key) throws(ConfigDecodingError) -> String? {
        try value(of: key, expected: .string, \.stringValue)
    }

    func bool(_ key: Key) throws(ConfigDecodingError) -> Bool? {
        try value(of: key, expected: .bool, \.boolValue)
    }

    func integer(_ key: Key) throws(ConfigDecodingError) -> Int? {
        try value(of: key, expected: .integer, \.integerValue)
    }

    func stringArray(_ key: Key) throws(ConfigDecodingError) -> [String]? {
        try value(of: key, expected: .stringArray, \.stringArrayValue)
    }

    func subtable<SubKey: ConfigKeySet>(
        _ key: Key,
        keys _: SubKey.Type
    ) throws(ConfigDecodingError) -> ConfigTableReader<SubKey>? {
        guard let subtable = try value(of: key, expected: .table, \.tableValue) else { return nil }
        return ConfigTableReader<SubKey>(table: subtable, tablePath: keyPath(of: key.rawValue))
    }

    /// このテーブルにある未知のキーのキーパス（順不同）
    var unknownKeyPaths: [String] {
        let knownKeys = Set(Key.allCases.map(\.rawValue))
        return table.keys
            .filter { !knownKeys.contains($0) }
            .map(keyPath(of:))
    }

    func error(_ key: Key, _ kind: ConfigDecodingError.Kind) -> ConfigDecodingError {
        ConfigDecodingError(key: keyPath(of: key.rawValue), kind: kind)
    }

    private func value<Value>(
        of key: Key,
        expected: ConfigValueType,
        _ extract: (TOMLValue) -> Value?
    ) throws(ConfigDecodingError) -> Value? {
        guard let value = table[key.rawValue] else { return nil }
        guard let extracted = extract(value) else {
            throw error(key, .typeMismatch(expected: expected, actual: ConfigValueType(of: value)))
        }
        return extracted
    }

    private func keyPath(of key: String) -> String {
        guard let tablePath else { return key }
        return tablePath + Self.keyPathSeparator + key
    }
}
