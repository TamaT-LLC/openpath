/// ghq 管理下のリポジトリを候補ソースにする（FR-SOURCE-03）。リポジトリはすべてディレクトリとして返す。
public struct GhqCandidateSource: CandidateSource {
    private let lister: GhqRepositoryLister

    /// - Parameter lister: login shell の PATH 取得を繰り返さないよう、共有の SearchPathProviding を渡したものを使うこと。
    public init(lister: GhqRepositoryLister) {
        self.lister = lister
    }

    public var kind: CandidateSourceKind {
        .ghq
    }

    /// 取得に失敗しても投げず、空の候補と `ghqFailed` の警告を返す（DSN-002 §3「失敗時は警告ログのみ」）。
    /// ghq の未インストールも警告に含めるため、利用者に知らせるかは受け取る側で決める。
    public func snapshot() async throws -> CandidateSourceSnapshot {
        let listing = await lister.listRepositories()
        // 一覧を取れていても、キャンセル後の結果で既存の候補を置き換えないよう投げる
        if listing.failure == .cancelled || Task.isCancelled {
            throw CancellationError()
        }
        let items = listing.repositoryPaths.map { SourceItem(path: $0, isDirectory: true) }
        let warnings = listing.failure.map { [CandidateSourceWarning.ghqFailed($0)] } ?? []
        return CandidateSourceSnapshot(items: items, warnings: warnings)
    }
}
