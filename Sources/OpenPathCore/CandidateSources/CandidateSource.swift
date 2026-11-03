/// 候補の出どころ（DSN-002 §2 の `Candidate.source`）。CandidateIndex はこれを単位に候補を差し替える。
public enum CandidateSourceKind: Sendable, Hashable {
    /// 設定 [favorites] の明示的なパス
    case favorites
    /// 確定履歴（HistoryStore）
    case history
    /// 設定 `roots` の 1 ルート。値はそのルートの絶対パス（設定の表記のまま）
    case root(String)
    /// ghq 管理下のリポジトリ
    case ghq
    /// zoxide のディレクトリ履歴。スコア・使用回数は取り込まない。
    case zoxide
}

/// 候補ソース（history / roots / ghq 共通。DSN-002 §3）。
///
/// 再構築のたびに `snapshot()` で現時点の中身をまとめて取り直す。
/// 明示的な別名は SourceItem に添え、frecency の付与・統合・順位付けは CandidateIndex が行う。
public protocol CandidateSource: Sendable {
    var kind: CandidateSourceKind { get }

    /// 現時点の候補を集める。
    ///
    /// ルートが無い・ghq が無いといった失敗ではエラーを投げず、集められた分の候補と警告を返す。
    /// キャンセルされた場合だけ `CancellationError` を投げる。途中までの結果で既存の候補を置き換えないようにするため。
    func snapshot() async throws -> CandidateSourceSnapshot
}
