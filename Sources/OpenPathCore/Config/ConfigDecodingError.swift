/// 設定値のデコードエラー。
///
/// `TOMLTable` はキーの出現位置を持たないため、行番号の代わりにキーパスで位置を示す。
public struct ConfigDecodingError: Error, Equatable, Sendable {
    /// ドット区切りのキーパス（例: `depth`, `ghq.enabled`）
    public let key: String
    public let kind: Kind

    public init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        case typeMismatch(expected: ConfigValueType, actual: ConfigValueType)
        /// 整数が下限を下回っている
        case belowMinimum(value: Int, minimum: Int)
        /// `roots` の要素が絶対パスに解決できない（相対パス、`~user` 形式など）
        case invalidRootPath(String)
        case invalidHotkey(HotkeyParseError)
    }
}

/// 設定値の型。型不一致のエラーで期待値と実際の値を示すのに使う
public enum ConfigValueType: Sendable, Equatable, CaseIterable {
    case string
    case bool
    case integer
    case stringArray
    case table
}

extension ConfigValueType {
    init(of value: TOMLValue) {
        switch value {
        case .string: self = .string
        case .bool: self = .bool
        case .integer: self = .integer
        case .stringArray: self = .stringArray
        case .table: self = .table
        }
    }

    fileprivate var displayName: String {
        switch self {
        case .string: "文字列"
        case .bool: "真偽値"
        case .integer: "整数"
        case .stringArray: "文字列の配列"
        case .table: "テーブル"
        }
    }
}

extension ConfigDecodingError: CustomStringConvertible {
    public var description: String {
        "設定 '\(key)': \(kind.message)"
    }
}

private extension ConfigDecodingError.Kind {
    var message: String {
        switch self {
        case .typeMismatch(let expected, let actual):
            "\(expected.displayName)を指定してください（実際の値は\(actual.displayName)）"
        case .belowMinimum(let value, let minimum):
            "\(minimum) 以上を指定してください（実際の値は \(value)）"
        case .invalidRootPath(let path):
            "'\(path)' は絶対パスか ~ で始まるパスで指定してください"
        case .invalidHotkey(let error):
            error.description
        }
    }
}
