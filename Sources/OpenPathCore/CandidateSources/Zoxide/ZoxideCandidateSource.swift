/// zoxide のディレクトリ履歴を候補にする。スコア・時刻はインポートせず、種別をローカルで確かめる。
public struct ZoxideCandidateSource: CandidateSource {
    private let lister: ZoxideDirectoryLister

    public init(lister: ZoxideDirectoryLister) { self.lister = lister }
    public var kind: CandidateSourceKind { .zoxide }

    /// 不存在・ファイル・パッケージを除き、他ソースと同じパスで統合できるディレクトリだけを返す。
    /// キャンセル時は空で上書きせず投げ、それ以外の失敗では警告を添えた空の候補にする。
    public func snapshot() async throws -> CandidateSourceSnapshot {
        let listing = await lister.listDirectories()
        if listing.failure == .cancelled || Task.isCancelled { throw CancellationError() }
        var items: [SourceItem] = []
        for path in listing.directoryPaths {
            try Task.checkCancellation()
            if FileSystemItemKind.ofItem(atPath: path) == .directory {
                items.append(SourceItem(path: path, isDirectory: true))
            }
        }
        let warnings = listing.failure.map { [CandidateSourceWarning.zoxideFailed($0)] } ?? []
        return CandidateSourceSnapshot(items: items, warnings: warnings)
    }
}
