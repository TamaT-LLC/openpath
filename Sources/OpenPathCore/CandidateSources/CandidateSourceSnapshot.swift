/// 候補ソースの 1 回分の収集結果。
public struct CandidateSourceSnapshot: Sendable, Equatable {
    public let items: [SourceItem]
    /// 収集は続けられたが利用者に知らせたい事象。ログやフッターの表示に使う
    public let warnings: [CandidateSourceWarning]

    public init(items: [SourceItem], warnings: [CandidateSourceWarning] = []) {
        self.items = items
        self.warnings = warnings
    }
}

/// 候補の収集中に起きた、エラーにはしない事象。
public enum CandidateSourceWarning: Sendable, Equatable {
    /// ルートを走査できなかったため、そのルートの候補は空になった
    case rootUnavailable(root: String, reason: RootUnavailableReason)
    /// ルート配下の候補が上限件数に達したため、以降の走査を打ち切った（DSN-002 §3）
    case rootTruncated(root: String, limit: Int)
    /// ghq の一覧を取得できなかった（未インストールを含む）。ghq の候補は空になった
    case ghqFailed(GhqError)
}

/// ルートを走査できなかった理由。
public enum RootUnavailableReason: Sendable, Equatable {
    /// 存在しない（リンク切れのシンボリックリンクを含む）
    case notFound
    /// ディレクトリではない
    case notDirectory
    /// 中身を一覧できる権限が無い
    case unreadable
}
