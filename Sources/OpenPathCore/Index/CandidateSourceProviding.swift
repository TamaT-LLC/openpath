/// 設定から候補ソースの一覧を組み立てる。CandidateIndexRebuilder が再構築のたびに呼ぶ。
public protocol CandidateSourceProviding: Sendable {
    /// `config` のときに候補を集めるソース。同じ kind のソースは 1 つにすること（重複は先勝ちで無視する）。
    func sources(for config: Config) -> [any CandidateSource]
}

/// 本番の候補ソース: 確定履歴・設定の roots（1 ルート 1 ソース）・ghq（`ghq.enabled` のときだけ）。DSN-002 §3。
public struct StandardCandidateSources: CandidateSourceProviding {
    private let history: HistoryCandidateSource
    private let searchPathProvider: any SearchPathProviding

    /// - Parameters:
    ///   - history: 確定履歴のソース。
    ///   - searchPathProvider: ghq を探す検索パスの取得元。login shell の起動を繰り返さないよう、
    ///     ConfigStore の ghq root の取得などと共有すること。
    public init(history: HistoryCandidateSource, searchPathProvider: any SearchPathProviding) {
        self.history = history
        self.searchPathProvider = searchPathProvider
    }

    public func sources(for config: Config) -> [any CandidateSource] {
        let roots: [any CandidateSource] = RootCandidateSource.sources(for: config)
        var sources: [any CandidateSource] = [history] + roots
        if config.ghq.enabled {
            let lister = GhqRepositoryLister(isEnabled: true, searchPathProvider: searchPathProvider)
            sources.append(GhqCandidateSource(lister: lister))
        }
        return sources
    }
}
