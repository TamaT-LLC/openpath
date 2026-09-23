/// 確定履歴を候補ソースにする（FR-SOURCE-01）。
///
/// HistoryStore は MainActor に隔離されているため、MainActor 上では履歴の写しを取るだけにし、
/// ファイルシステムを読む種別の判定はその外で行う。
/// 存在しないパスは種別（ディレクトリかどうか）を決められないため含めない。
/// frecency と最終使用日時は候補に持たせないので、CandidateIndex が HistoryStore から引くこと。
public struct HistoryCandidateSource: CandidateSource {
    private let entries: @MainActor @Sendable () -> [HistoryEntry]

    public init(store: HistoryStore) {
        self.init { store.entries }
    }

    /// - Parameter entries: 現時点の履歴を返す。MainActor 上で呼ぶ。
    public init(entries: @escaping @MainActor @Sendable () -> [HistoryEntry]) {
        self.entries = entries
    }

    public var kind: CandidateSourceKind {
        .history
    }

    /// 履歴の順（初出順）に、実在するパスをリンク先の種別で返す。パッケージ（`.app` 等）はファイルとして扱う。
    public func snapshot() async throws -> CandidateSourceSnapshot {
        let paths = await entries().map(\.path)
        try Task.checkCancellation()
        var items: [SourceItem] = []
        for path in paths {
            try Task.checkCancellation()
            guard let kind = FileSystemItemKind.ofItem(atPath: path) else {
                continue
            }
            items.append(SourceItem(path: path, isDirectory: kind == .directory))
        }
        return CandidateSourceSnapshot(items: items)
    }
}
