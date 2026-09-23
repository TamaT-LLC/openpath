import Foundation

/// クエリ 1 回分の順位付け（DSN-002 §4〜§5）。`CandidateIndex.query` のうち、履歴を取得した後の同期部分。
///
/// 1. 空クエリ: マッチを行わず frecency の降順。履歴が足りなければ履歴のない候補をパスの昇順で補う
/// 2. それ以外: name / path へのファジーマッチのスコア × (1 + log1p(frecency)) の降順
/// 3. 並べた順に存在を確かめ、存在しない候補を飛ばして `limit` 件まで集める（FR-HISTORY-03）
///
/// 同点は最終使用日時の新しい順（履歴にない候補は後ろ）、さらにパスの昇順とし、順序を決定的にする
/// （HistoryList.sortedByFrecency と同じ規則）。
struct CandidateRanker: Sendable {
    let matcher: FuzzyMatcher
    let fileExistence: any FileExistenceChecking
    /// 候補数がこれ以上なら前置フィルタを使う
    let prefilterThreshold: Int

    func rank(
        _ text: String,
        in catalog: CandidateCatalog,
        history: HistoryLookup,
        directoriesOnly: Bool,
        limit: Int
    ) throws -> [RankedCandidate] {
        guard limit > 0 else { return [] }
        let query = matcher.prepareQuery(text)
        if query.codes.isEmpty {
            let ordered = try orderByFrecency(catalog, history: history, directoriesOnly: directoriesOnly)
            return try existingCandidates(ordered, in: catalog, history: history, matches: [], limit: min(limit, CandidateIndex.emptyQueryLimit))
        }
        let (ordered, matches) = try orderByMatch(query, in: catalog, history: history, directoriesOnly: directoriesOnly)
        return try existingCandidates(ordered, in: catalog, history: history, matches: matches, limit: limit)
    }

    private func orderByFrecency(
        _ catalog: CandidateCatalog,
        history: HistoryLookup,
        directoriesOnly: Bool
    ) throws -> some Sequence<RankKey> {
        let isEligible = { (index: Int) in !directoriesOnly || catalog.entries[index].isDirectory }
        var used: [RankKey] = []
        for index in history.usedIndices where isEligible(index) {
            try Task.checkCancellation()
            guard let usage = history.usage(at: index) else { continue }
            used.append(RankKey(score: usage.frecency, usage: usage, index: index, matchSlot: nil))
        }
        used.sort(by: RankKey.ranksHigher)
        // 履歴のない候補は frecency 0・最終使用日時なしで同点のため、添字の昇順（パスの昇順）がそのまま順位になる。
        // 存在確認で必要になった分だけ取り出すよう遅延させる
        let unused = catalog.entries.indices.lazy
            .filter { isEligible($0) && history.usage(at: $0) == nil }
            .map { RankKey(score: 0, usage: nil, index: $0, matchSlot: nil) }
        return [AnySequence(used), AnySequence(unused)].joined()
    }

    /// マッチした候補の順位と、マッチ結果（`RankKey.matchSlot` で指す）を返す。
    /// 並べ替えは軽い値（RankKey）だけで行い、一致位置の配列を持つマッチ結果は動かさない
    private func orderByMatch(
        _ query: FuzzyQuery,
        in catalog: CandidateCatalog,
        history: HistoryLookup,
        directoriesOnly: Bool
    ) throws -> (ordered: [RankKey], matches: [FuzzyCandidateMatch]) {
        let indices = catalog.entries.count >= prefilterThreshold
            ? catalog.prefilteredIndices(for: query)
            : Array(catalog.entries.indices)
        var keys: [RankKey] = []
        var matches: [FuzzyCandidateMatch] = []
        for index in indices {
            try Task.checkCancellation()
            let entry = catalog.entries[index]
            guard !directoriesOnly || entry.isDirectory,
                  let match = matcher.scoreCandidate(query: query, name: entry.targets.name, path: entry.targets.path)
            else {
                continue
            }
            let usage = history.usage(at: index)
            let score = Double(match.score) * (1 + log1p(usage?.frecency ?? 0))
            keys.append(RankKey(score: score, usage: usage, index: index, matchSlot: matches.count))
            matches.append(match)
        }
        keys.sort(by: RankKey.ranksHigher)
        return (keys, matches)
    }

    /// 並べた順に存在を確かめ、存在する候補だけを `limit`（1 以上）件まで集める。確認は必要な件数に達した時点でやめる
    private func existingCandidates(
        _ ordered: some Sequence<RankKey>,
        in catalog: CandidateCatalog,
        history: HistoryLookup,
        matches: [FuzzyCandidateMatch],
        limit: Int
    ) throws -> [RankedCandidate] {
        var results: [RankedCandidate] = []
        for key in ordered {
            try Task.checkCancellation()
            let entry = catalog.entries[key.index]
            guard fileExistence.fileExists(atPath: entry.path) else { continue }
            let usage = history.usage(at: key.index)
            let candidate = Candidate(
                path: entry.path,
                name: CandidatePath.name(of: entry.path),
                isDirectory: entry.isDirectory,
                source: entry.source,
                frecency: usage?.frecency ?? 0,
                lastUsed: usage?.lastUsed
            )
            results.append(RankedCandidate(candidate: candidate, match: key.matchSlot.map { matches[$0] }, score: key.score))
            if results.count == limit {
                break
            }
        }
        return results
    }
}

/// 順位付けの途中の 1 件。並べ替えを軽くするため、候補は CandidateCatalog の添字、マッチ結果は別の配列の添字で指す
private struct RankKey {
    /// 最終使用日時の無い（履歴にない）候補を、ある候補より後ろにするための値
    private static let neverUsed = -Double.infinity

    let score: Double
    /// 最終使用日時（基準日時からの秒数）
    let lastUsed: Double
    let index: Int
    let matchSlot: Int?

    init(score: Double, usage: HistoryLookup.Usage?, index: Int, matchSlot: Int?) {
        self.score = score
        lastUsed = usage?.lastUsed.timeIntervalSinceReferenceDate ?? Self.neverUsed
        self.index = index
        self.matchSlot = matchSlot
    }

    static func ranksHigher(_ lhs: RankKey, _ rhs: RankKey) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.lastUsed != rhs.lastUsed {
            return lhs.lastUsed > rhs.lastUsed
        }
        return lhs.index < rhs.index
    }
}
