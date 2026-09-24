import Foundation
import os

/// 候補ソース（history / roots / ghq）の候補を統合し、ファジーマッチと frecency で順位付けして返す（DSN-002 §2〜§5）。
///
/// 並行性:
/// - 統合済みの候補は不変の値（CandidateCatalog）で持ち、差し替えのたびに作り直してロック下で丸ごと入れ替える。
///   ロックを持つのは値の読み書きの間だけで、前処理・統合・マッチはロックの外で行う。
///   そのため差し替え（走査結果の反映）の途中でもクエリは直前の候補で答え、互いを待たない。
/// - `replace` と `query` は nonisolated な async メソッドで、呼び出し元のアクター（MainActor）ではなく
///   並行実行用のスレッドで動く。パレットの入力ごとのクエリがメインスレッドを占有しないようにするため。
///   （upcoming feature の NonisolatedNonsendingByDefault を有効にすると呼び出し元で動くようになるため、
///   その際は `@concurrent` を付けること）
/// - frecency と最終使用日時は MainActor に隔離された HistoryStore の値を使う。クエリのたびに履歴の写しだけを
///   MainActor 上で受け取り（配列の参照を渡すだけ）、計算はその外で行う。
public final class CandidateIndex: Sendable {
    /// 空クエリで返す件数の上限（UX-001 §2「frecency 上位 8 件を初期表示」）
    public static let emptyQueryLimit = 8
    /// 候補がこの件数以上なら、クエリの先頭 2 文字で前置フィルタしてからマッチする（DSN-002 §5）
    public static let prefilterThreshold = 10_000

    private struct State: Sendable {
        /// ソースごとの前処理済みの候補
        var sources: [CandidateSourceKind: [PreparedCandidate]] = [:]
        /// `sources` を更新するたびに増やす
        var revision = 0
        var catalog = CandidateCatalog.empty
        /// `catalog` の元になった `sources` の revision
        var catalogRevision = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let preparer: CandidatePreparer
    private let ranker: CandidateRanker
    private let now: @Sendable () -> Date
    private let history: @MainActor @Sendable () -> [HistoryEntry]

    /// - Parameters:
    ///   - historyStore: frecency と最終使用日時の取得元。
    ///   - fileExistence: 表示直前の存在確認に使う。
    ///   - now: frecency の減衰の計算に使う。
    public convenience init(
        historyStore: HistoryStore,
        matcher: FuzzyMatcher = FuzzyMatcher(),
        fileExistence: any FileExistenceChecking = LocalFileExistenceChecker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(matcher: matcher, fileExistence: fileExistence, now: now) { historyStore.entries }
    }

    /// - Parameter history: 現時点の履歴を返す。クエリのたびに MainActor 上で呼ぶ。
    public convenience init(
        matcher: FuzzyMatcher = FuzzyMatcher(),
        fileExistence: any FileExistenceChecking = LocalFileExistenceChecker(),
        now: @escaping @Sendable () -> Date = { Date() },
        history: @escaping @MainActor @Sendable () -> [HistoryEntry]
    ) {
        self.init(matcher: matcher, fileExistence: fileExistence, now: now, prefilterThreshold: Self.prefilterThreshold, history: history)
    }

    /// - Parameter prefilterThreshold: テストで前置フィルタの有無を切り替えるために差し替える。
    init(
        matcher: FuzzyMatcher = FuzzyMatcher(),
        fileExistence: any FileExistenceChecking,
        now: @escaping @Sendable () -> Date,
        prefilterThreshold: Int,
        history: @escaping @MainActor @Sendable () -> [HistoryEntry]
    ) {
        preparer = CandidatePreparer(matcher: matcher)
        ranker = CandidateRanker(matcher: matcher, fileExistence: fileExistence, prefilterThreshold: prefilterThreshold)
        self.now = now
        self.history = history
    }

    /// 統合後の候補数（最後に反映した差し替えの時点）
    public var count: Int {
        state.withLock { $0.catalog.entries.count }
    }

    /// `source` の候補を `items` で置き換える。空なら `source` の候補を取り除く。
    ///
    /// 前処理（正規化）は 1 件あたり数十 µs かかるため、呼び出し元のスレッドではなく並行実行用のスレッドで行う。
    /// 異なるソースの差し替えが並行しても、すべての差し替えを反映した候補が最後に残る。
    /// 同じソースの差し替えが並行した場合は後に反映した方が残るため、同じソースの走査は直列にすること。
    ///
    /// 前処理した候補（パスと種別の並び）が今の `source` の候補と同じなら、何もせずに false を返す。
    /// 統合し直すと全ソースの候補数に比例した CPU と一時的なメモリを使うため、周期の再構築で前回と同じ候補を
    /// 返したソースでは省く（Issue #78）。
    /// - Returns: 候補を差し替えたか。
    @discardableResult
    public func replace(source: CandidateSourceKind, with items: [SourceItem]) async -> Bool {
        let (previous, current) = state.withLock { ($0.catalog, $0.sources[source] ?? []) }
        // 大半は正規化済み・重複なしの同じ並びで届くため、前処理の前に比べて前処理も省く
        if current.elementsEqual(items, by: { $0.path == $1.path && $0.isDirectory == $1.isDirectory }) {
            return false
        }
        let prepared = preparer.prepare(items, reusing: previous)
        if current.elementsEqual(prepared, by: { $0.path == $1.path && $0.isDirectory == $1.isDirectory }) {
            return false
        }
        let (sources, revision) = state.withLock { state in
            state.sources[source] = prepared.isEmpty ? nil : prepared
            state.revision += 1
            return (state.sources, state.revision)
        }
        let catalog = CandidateCatalog(merging: sources)
        state.withLock { state in
            // 後から始まった差し替えが先に反映済みなら、古い統合結果で上書きしない
            guard revision > state.catalogRevision else { return }
            state.catalog = catalog
            state.catalogRevision = revision
        }
        return true
    }

    /// `text` にマッチする候補を、総合スコア `fuzzyScore × (1 + log1p(frecency))` の降順で最大 `limit` 件返す。
    ///
    /// - 空のクエリ（正規化後に文字が残らないものを含む）はマッチを行わず、frecency の降順で最大 8 件
    ///   （`emptyQueryLimit` と `limit` の小さい方）返す。履歴が足りなければ履歴のない候補をパスの昇順で補う。
    /// - 返す直前に存在を確かめ、存在しない候補は除外して次の候補を繰り上げる（FR-HISTORY-03）。
    /// - Parameter directoriesOnly: true ならファイル（パッケージを含む）を返さない（FR-SOURCE-05）。
    /// - Throws: キャンセルされた場合は `CancellationError`。入力が続いて不要になったクエリを途中でやめるため。
    public func query(_ text: String, directoriesOnly: Bool, limit: Int) async throws -> [RankedCandidate] {
        let entries = await history()
        try Task.checkCancellation()
        let catalog = state.withLock { $0.catalog }
        let lookup = HistoryLookup(entries: entries, now: now(), catalog: catalog)
        return try ranker.rank(text, in: catalog, history: lookup, directoriesOnly: directoriesOnly, limit: limit)
    }
}
