import Foundation

/// 確定したパス 1 件分の使用履歴（FR-HISTORY-01）。`history.json` の要素になる。
public struct HistoryEntry: Codable, Sendable, Equatable {
    /// 呼び出し側で正規化済みのパス。履歴のキーとして文字列のまま比較する。
    public var path: String
    public var count: Int
    public var lastUsed: Date

    // ARCH-001 §8 の `{ path, count, last_used }` に合わせる
    private enum CodingKeys: String, CodingKey {
        case path
        case count
        case lastUsed = "last_used"
    }

    public init(path: String, count: Int, lastUsed: Date) {
        self.path = path
        self.count = count
        self.lastUsed = lastUsed
    }

    public func frecency(now: Date) -> Double {
        Frecency.score(count: count, lastUsed: lastUsed, now: now)
    }
}
