/// 設定 `roots` の 1 ルートを候補ソースにする（FR-SOURCE-02）。
///
/// ルートごとにソースを分け、CandidateIndex がルート単位で候補を差し替えられるようにする（kind は `.root(ルート)`）。
/// 走査の方針は RootDirectoryScanner を参照。
public struct RootCandidateSource: CandidateSource {
    public let root: String
    private let scanner: RootDirectoryScanner

    public init(root: String, scanner: RootDirectoryScanner) {
        self.root = root
        self.scanner = scanner
    }

    public init(root: String, options: RootScanOptions) {
        self.init(root: root, scanner: RootDirectoryScanner(options: options))
    }

    public var kind: CandidateSourceKind {
        .root(root)
    }

    /// ルートを走査する。ファイルシステムを同期的に読むため、DSN-002 §3 のとおり
    /// `Task.detached(priority: .utility)` などバックグラウンドのタスクから呼ぶこと。
    public func snapshot() async throws -> CandidateSourceSnapshot {
        try scanner.scan(root: root)
    }

    /// 設定の `roots` それぞれを、設定の `depth` / `include_files` / `ignore` で走査するソース。`roots` の順に並ぶ。
    public static func sources(for config: Config) -> [RootCandidateSource] {
        let scanner = RootDirectoryScanner(options: RootScanOptions(config: config))
        return config.roots.map { RootCandidateSource(root: $0, scanner: scanner) }
    }
}
