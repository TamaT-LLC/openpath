import Foundation

/// 確定したパスの履歴（DSN-002 §2, §4）。永続化は HistoryStore の責務で、ここでは純粋な値操作のみを扱う。
/// パスは呼び出し側で正規化済みの文字列をそのままキーにし、同一パスは常に 1 件に保つ。
public struct HistoryList: Sendable, Equatable {
    /// 保持する最大件数。超過時は frecency 下位から削除する。
    public static let maxEntryCount = 2_000

    private static let staleThresholdDays = 90.0

    /// この期間以上使われていないエントリを掃除の候補にする（FR-HISTORY-03）。
    public static let staleThreshold: TimeInterval = staleThresholdDays * HistoryTimeUnit.secondsPerDay

    /// 初出順。保存内容の差分を小さく保つため、frecency 順には並べ替えずに保持する。
    public private(set) var entries: [HistoryEntry]

    /// 手編集などで同一パスが重複していた場合は、初出の位置に 1 件へ統合する
    /// （count は合算、lastUsed は新しい方）。上限超過分は次の `record` で削る。
    public init(entries: [HistoryEntry] = []) {
        self.entries = Self.mergingDuplicates(entries)
    }

    public func entry(for path: String) -> HistoryEntry? {
        entries.first { $0.path == path }
    }

    /// 確定を記録する。既存なら count を 1 増やして lastUsed を更新し、新規なら count 1 で追加する。
    /// 上限を超えた場合は frecency 下位から削除するが、今回記録したパスは対象外にする
    /// （新規パスは count 1 のため、既存がすべて高スコアだと記録直後に消えてしまうのを防ぐ）。
    public mutating func record(path: String, now: Date) {
        if let index = entries.firstIndex(where: { $0.path == path }) {
            entries[index].count += 1
            entries[index].lastUsed = now
        } else {
            entries.append(HistoryEntry(path: path, count: 1, lastUsed: now))
        }
        evictOverflow(protecting: path, now: now)
    }

    /// frecency 降順。同点は lastUsed が新しい順、さらに同じならパスの昇順で並べて順序を決定的にする。
    public func sortedByFrecency(now: Date) -> [HistoryEntry] {
        entries
            .map { RankedEntry(entry: $0, score: $0.frecency(now: now)) }
            .sorted(by: RankedEntry.ranksHigher)
            .map(\.entry)
    }

    /// `staleThreshold` 以上使われておらず、かつ存在しないエントリを取り除いた履歴を返す。
    /// 一時的に外れた外部ボリューム等を消さないよう両方を満たす場合のみ削除する。
    /// 存在確認は古いエントリに限って行い、保存のたびに全件へファイルアクセスしないようにする。
    public func pruned(now: Date, fileExistence: some FileExistenceChecking) -> HistoryList {
        var copy = self
        copy.entries.removeAll { entry in
            let isStale = now.timeIntervalSince(entry.lastUsed) >= Self.staleThreshold
            return isStale && !fileExistence.fileExists(atPath: entry.path)
        }
        return copy
    }

    /// 並び順の末尾（frecency 最下位、同点なら lastUsed が古い方）から超過分を削除する。
    private mutating func evictOverflow(protecting protectedPath: String, now: Date) {
        let overflowCount = entries.count - Self.maxEntryCount
        guard overflowCount > 0 else { return }

        let evictedPaths = Set(
            sortedByFrecency(now: now)
                .reversed()
                .lazy
                .map(\.path)
                .filter { $0 != protectedPath }
                .prefix(overflowCount)
        )
        entries.removeAll { evictedPaths.contains($0.path) }
    }

    private static func mergingDuplicates(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var merged: [HistoryEntry] = []
        var indexByPath: [String: Int] = [:]
        for entry in entries {
            guard let index = indexByPath[entry.path] else {
                indexByPath[entry.path] = merged.count
                merged.append(entry)
                continue
            }
            merged[index].count += entry.count
            merged[index].lastUsed = max(merged[index].lastUsed, entry.lastUsed)
        }
        return merged
    }
}

/// 並べ替えのたびに frecency を再計算しないよう、スコアを添えて比較する。
private struct RankedEntry {
    let entry: HistoryEntry
    let score: Double

    static func ranksHigher(_ lhs: RankedEntry, _ rhs: RankedEntry) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.entry.lastUsed != rhs.entry.lastUsed {
            return lhs.entry.lastUsed > rhs.entry.lastUsed
        }
        return lhs.entry.path < rhs.entry.path
    }
}
