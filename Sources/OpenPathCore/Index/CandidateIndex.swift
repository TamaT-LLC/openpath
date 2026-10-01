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
/// - ソースごとに差し替えの世代を持つ。`invalidate(source:)` で世代を進めると、それより前に取った世代での
///   差し替え（無効にする前に始めた収集の結果）は反映しない（Issue #92）。
public final class CandidateIndex: Sendable {
    /// 空クエリで返す件数の上限（UX-001 §2「frecency 上位 8 件を初期表示」）
    public static let emptyQueryLimit = 8
    /// 候補がこの件数以上なら、クエリの先頭 2 文字で前置フィルタしてからマッチする（DSN-002 §5）
    public static let prefilterThreshold = 10_000

    /// ソースの差し替えの世代。収集を始める前に `generation(of:)` で取り、`replace(source:with:generation:)` に渡す
    struct Generation: Sendable, Equatable {
        fileprivate let value: Int
    }

    /// 世代を指定した差し替えの結果
    enum ReplaceOutcome: Sendable, Equatable {
        /// 候補を差し替えた
        case replaced
        /// 前処理した候補が今の候補と同じだったため、何もしなかった
        case unchanged
        /// 世代を取った後にソースを無効にされていたため、反映しなかった
        case superseded
    }

    /// ソースを無効にした結果（`invalidateCountingRemoved(source:)`）
    struct SourceInvalidation: Sendable {
        /// 取り除いたソースの候補の数
        let removedCount: Int
        /// 呼んだ時点のソースの候補をクエリに反映し終える Task（`invalidate(source:)` の戻り値と同じ）
        let publication: Task<Void, Never>
    }

    private struct State: Sendable {
        /// ソースごとの前処理済みの候補
        var sources: [CandidateSourceKind: [PreparedCandidate]] = [:]
        /// `sources` を更新するたびに増やす
        var revision = 0
        var catalog = CandidateCatalog.empty
        /// `catalog` の元になった `sources` の revision
        var catalogRevision = 0
        /// ソースごとの差し替えの世代。`invalidate(source:)` のたびに進める（無いソースは 0）
        var generations: [CandidateSourceKind: Int] = [:]

        /// `source` の今の差し替えの世代
        func generation(of source: CandidateSourceKind) -> Generation {
            Generation(value: generations[source] ?? 0)
        }

        /// `expected` が nil（世代を問わない差し替え）か、今の世代と同じか
        func isCurrent(_ expected: Generation?, of source: CandidateSourceKind) -> Bool {
            expected.map { $0 == generation(of: source) } ?? true
        }
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
        await replace(source: source, with: items, expecting: nil) == .replaced
    }

    /// `source` の今の差し替えの世代。収集を始める前に取り、その結果の差し替えに渡す。
    func generation(of source: CandidateSourceKind) -> Generation {
        state.withLock { $0.generation(of: source) }
    }

    /// `generation` を取った後に `source` を無効にされていなければ、`replace(source:with:)` と同じく差し替える。
    ///
    /// 世代の照合と候補の書き込みは同じロックの中で行うため、`invalidate(source:)` と並行しても、
    /// 無効にする前に取った世代の候補が無効にした後に残ることはない。
    func replace(source: CandidateSourceKind, with items: [SourceItem], generation: Generation) async -> ReplaceOutcome {
        await replace(source: source, with: items, expecting: generation)
    }

    /// `source` の候補を直ちに取り除き、世代を進める。以後、それより前に取った世代での差し替えは反映しない。
    ///
    /// 走査中の再構築の終わりを待たずに候補を消すためのもの（履歴のクリア。Issue #92）。候補が無くても世代は進める
    /// （起動時の最初の差し替えより前に消した場合も、消す前に読んだ収集の結果を反映しないため）。
    /// 世代とソースの候補は呼んだ時点で（同期的に）更新する。クエリが使う統合済みの候補は全ソースの候補数に比例した
    /// CPU を使うため、並行実行用のスレッドで作り直す。
    /// - Returns: 呼んだ時点のソースの候補（取り除いた後）をクエリに反映し終える Task。取り除く候補が無くても、
    ///   先に取り除いた分などの反映が済んでいなければ、それを含めて反映するまで終わらない（続けて呼んだ場合に、
    ///   後の呼び出しの完了を待った側が、まだ取り除かれていない候補で引き直さないようにするため）。
    @discardableResult
    func invalidate(source: CandidateSourceKind) -> Task<Void, Never> {
        invalidateCountingRemoved(source: source).publication
    }

    /// `invalidate(source:)` と同じく取り除き、取り除いた候補の数も返す（履歴のクリアの診断用）。
    func invalidateCountingRemoved(source: CandidateSourceKind) -> SourceInvalidation {
        typealias Pending = (sources: [CandidateSourceKind: [PreparedCandidate]], revision: Int)
        let (removedCount, pending): (Int, Pending?) = state.withLock { state in
            state.generations[source, default: 0] += 1
            let removed = state.sources.removeValue(forKey: source)
            if removed != nil {
                state.revision += 1
            }
            // クエリが使う候補が今のソースの候補に追いついていれば、作り直す必要は無い
            guard state.catalogRevision < state.revision else { return (removed?.count ?? 0, nil) }
            return (removed?.count ?? 0, (state.sources, state.revision))
        }
        guard let pending else { return SourceInvalidation(removedCount: removedCount, publication: Task {}) }
        // 利用者の操作（メニュー）の結果で、表示中のパレットがこの反映を待つため、走査（utility）より優先する
        let publication = Task.detached(priority: .userInitiated) { [self] in
            publishCatalog(merging: pending.sources, revision: pending.revision)
        }
        return SourceInvalidation(removedCount: removedCount, publication: publication)
    }

    /// 差し替えの本体。`expected` が nil なら世代を問わない。
    private func replace(source: CandidateSourceKind, with items: [SourceItem], expecting expected: Generation?) async -> ReplaceOutcome {
        let base: (previous: CandidateCatalog, current: [PreparedCandidate])? = state.withLock { state in
            guard state.isCurrent(expected, of: source) else { return nil }
            return (state.catalog, state.sources[source] ?? [])
        }
        guard let base else { return .superseded }
        // 大半は正規化済み・重複なしの同じ並びで届くため、前処理の前に比べて前処理も省く
        if base.current.elementsEqual(items, by: { $0.path == $1.path && $0.isDirectory == $1.isDirectory }) {
            return .unchanged
        }
        let prepared = preparer.prepare(items, reusing: base.previous)
        if base.current.elementsEqual(prepared, by: { $0.path == $1.path && $0.isDirectory == $1.isDirectory }) {
            return .unchanged
        }
        let updated: (sources: [CandidateSourceKind: [PreparedCandidate]], revision: Int)? = state.withLock { state in
            // 前処理の間に無効にされていたら書き込まない
            guard state.isCurrent(expected, of: source) else { return nil }
            state.sources[source] = prepared.isEmpty ? nil : prepared
            state.revision += 1
            return (state.sources, state.revision)
        }
        guard let updated else { return .superseded }
        publishCatalog(merging: updated.sources, revision: updated.revision)
        return .replaced
    }

    /// `sources` を統合し、クエリが使う候補にする。
    private func publishCatalog(merging sources: [CandidateSourceKind: [PreparedCandidate]], revision: Int) {
        let catalog = CandidateCatalog(merging: sources)
        state.withLock { state in
            // 後から始まった差し替えが先に反映済みなら、古い統合結果で上書きしない
            guard revision > state.catalogRevision else { return }
            state.catalog = catalog
            state.catalogRevision = revision
        }
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
