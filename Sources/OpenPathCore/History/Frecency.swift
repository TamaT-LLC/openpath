import Foundation

/// 使用頻度（count）と最終使用からの経過時間を組み合わせたスコア（DSN-002 §4）。
/// zoxide の aging を簡略化し、経過時間を 4 段階の減衰係数に丸める。
public enum Frecency {
    /// `elapsed` がこの秒数「未満」なら `factor` を採用する区間。
    private struct DecayTier: Sendable {
        let upperBound: TimeInterval
        let factor: Double
    }

    /// 上限の昇順に並べる。境界ちょうどの値は次の（小さい係数の）区間に入る。
    private static let decayTiers: [DecayTier] = [
        DecayTier(upperBound: HistoryTimeUnit.secondsPerHour, factor: 4.0),
        DecayTier(upperBound: HistoryTimeUnit.secondsPerDay, factor: 2.0),
        DecayTier(upperBound: HistoryTimeUnit.secondsPerWeek, factor: 0.5),
    ]

    /// 1 週間以上使われていない場合の減衰係数。
    private static let oldestDecayFactor = 0.25

    /// 最終使用からの経過秒数に対する減衰係数。
    /// 負の値（時計の巻き戻りで lastUsed が未来）は「直前に使った」とみなし最大の係数を返す。
    public static func decay(elapsed: TimeInterval) -> Double {
        decayTiers.first { elapsed < $0.upperBound }?.factor ?? oldestDecayFactor
    }

    /// `count × decay(now - lastUsed)`。
    public static func score(count: Int, lastUsed: Date, now: Date) -> Double {
        Double(count) * decay(elapsed: now.timeIntervalSince(lastUsed))
    }
}
