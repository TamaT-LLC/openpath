/// GhqRepositoryLister が実行する ghq のサブコマンド。
public enum GhqSubcommand: Sendable {
    /// `ghq root`
    case root
    /// `ghq list -p`
    case list

    /// ghq に渡す引数。ネットワーク通信を伴うサブコマンド（get 等）はここに加えないこと（NFR-01）。
    var arguments: [String] {
        switch self {
        case .root:
            ["root"]
        case .list:
            ["list", "-p"]
        }
    }
}

/// ghq からリポジトリ一覧を得られなかった理由。
public enum GhqError: Error, Equatable, Sendable {
    /// 検索パス上に ghq の実行ファイルが無い（未インストール）。
    case notInstalled(searchPath: String)
    /// ghq を起動できなかった。
    case launchFailed(GhqSubcommand, reason: String)
    /// ghq が非ゼロで終了した。standardError は前後の空白・改行を除いたもの。
    case nonZeroExit(GhqSubcommand, exitCode: Int32, standardError: String)
    /// ghq がタイムアウトまでに終了しなかった。
    case timedOut(GhqSubcommand)
    /// `ghq root` の出力が空だった。
    case emptyRoot
    /// 呼び出し元のタスクがキャンセルされた。
    case cancelled
}

/// ghq のリポジトリ一覧の取得結果。失敗しても一覧は空として扱えるよう、理由と分けて持つ。
public struct GhqListing: Equatable, Sendable {
    /// リポジトリの絶対パス。失敗時・無効時は空。
    public let repositoryPaths: [String]
    /// 失敗した理由。成功時と、設定で無効化されていて何も実行しなかったときは nil。
    public let failure: GhqError?

    public init(repositoryPaths: [String], failure: GhqError?) {
        self.repositoryPaths = repositoryPaths
        self.failure = failure
    }
}
