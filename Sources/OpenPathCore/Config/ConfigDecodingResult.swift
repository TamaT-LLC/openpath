/// デコード結果。設定は有効なまま、利用者に知らせたい注意点を `warnings` に持つ
public struct ConfigDecodingResult: Sendable, Equatable {
    public let config: Config
    /// キーパスの昇順
    public let warnings: [ConfigWarning]

    public init(config: Config, warnings: [ConfigWarning]) {
        self.config = config
        self.warnings = warnings
    }
}

/// デコードを止めるほどではない設定ファイルの問題
public enum ConfigWarning: Sendable, Equatable {
    /// 未知のキー（ドット区切りのキーパス）。タイプミスやテーブル内への書き間違いに気づけるよう無視せず知らせる
    case unknownKey(String)
}

extension ConfigWarning: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknownKey(let key): "未知のキー '\(key)' を無視しました"
        }
    }
}
