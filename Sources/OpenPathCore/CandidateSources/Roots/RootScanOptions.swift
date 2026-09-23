/// roots 走査の条件（FR-SOURCE-02 / 05, DSN-002 §3）。
public struct RootScanOptions: Sendable, Equatable {
    /// 1 ルートあたりの候補数の上限。巨大なディレクトリで走査時間とメモリが膨らむのを防ぐ（DSN-002 §3）
    public static let defaultItemLimit = 20_000

    /// ルート直下を 1 とした走査の深さ。0 以下ならルート自身のみ
    public let depth: Int
    /// ファイルも候補に含めるか。false ならディレクトリのみ
    public let includeFiles: Bool
    /// 名前がこれと完全一致する項目を除外し、ディレクトリなら配下にも潜らない。ルート自身には適用しない
    public let ignoredNames: Set<String>
    /// 1 ルートあたりの候補数の上限。ルート自身も 1 件に数える
    public let itemLimit: Int

    public init(
        depth: Int = Config.defaultDepth,
        includeFiles: Bool = Config.defaultIncludeFiles,
        ignoredNames: Set<String> = Set(Config.defaultIgnore),
        itemLimit: Int = defaultItemLimit
    ) {
        self.depth = depth
        self.includeFiles = includeFiles
        self.ignoredNames = ignoredNames
        self.itemLimit = itemLimit
    }

    /// 設定の `depth` / `include_files` / `ignore` から作る。
    public init(config: Config, itemLimit: Int = defaultItemLimit) {
        self.init(
            depth: config.depth,
            includeFiles: config.includeFiles,
            ignoredNames: Set(config.ignore),
            itemLimit: itemLimit
        )
    }
}
