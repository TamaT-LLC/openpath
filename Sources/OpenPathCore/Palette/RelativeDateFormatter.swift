import Foundation

/// 候補の最終使用日時を「3分前」「2日前」のような相対表記にする（UX-001 §3、日本語固定）。
///
/// Foundation の RelativeDateTimeFormatter は ICU のバージョンで空白や「今」の表記が変わり、
/// 列幅やテストが揺れるため、表記を自前で固定する。
/// 経過時間は暦（Calendar）ではなく経過秒で判定し、夏時間やタイムゾーンの影響を受けないようにする。
public enum RelativeDateFormatter {
    private static let justNow = "たった今"

    private static let secondsPerMinute: TimeInterval = 60
    private static let secondsPerHour: TimeInterval = 60 * secondsPerMinute
    private static let secondsPerDay: TimeInterval = 24 * secondsPerHour
    private static let secondsPerWeek: TimeInterval = 7 * secondsPerDay
    /// 月・年は暦に依らない概数で扱う
    private static let secondsPerMonth: TimeInterval = 30 * secondsPerDay
    private static let secondsPerYear: TimeInterval = 365 * secondsPerDay
    /// 壊れた履歴などで極端に古い日時が来ても、Int への変換で落ちないようにする上限
    private static let maximumCount: Double = 9999

    /// 経過時間が `upperBound` 未満なら `unit` で割った値（切り捨て）に `suffix` を付けて表す。
    private struct Unit {
        let upperBound: TimeInterval
        let unit: TimeInterval
        let suffix: String
    }

    /// 小さい単位から順に並べる。最初に `upperBound` を下回った単位を使う
    private static let units: [Unit] = [
        Unit(upperBound: secondsPerHour, unit: secondsPerMinute, suffix: "分前"),
        Unit(upperBound: secondsPerDay, unit: secondsPerHour, suffix: "時間前"),
        Unit(upperBound: secondsPerWeek, unit: secondsPerDay, suffix: "日前"),
        Unit(upperBound: secondsPerMonth, unit: secondsPerWeek, suffix: "週間前"),
        Unit(upperBound: secondsPerYear, unit: secondsPerMonth, suffix: "か月前"),
        Unit(upperBound: .infinity, unit: secondsPerYear, suffix: "年前"),
    ]

    /// - Parameters:
    ///   - date: 最終使用日時。nil（履歴にない候補）は空文字列を返す
    ///   - now: 基準時刻。テストでは固定値を渡す
    public static func string(from date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "" }
        let elapsed = now.timeIntervalSince(date)
        // 未来の日時（時計のずれ等）も 1 分未満と同じく扱う
        guard elapsed >= secondsPerMinute else { return justNow }
        guard let unit = units.first(where: { elapsed < $0.upperBound }) else { return justNow }
        return "\(Int(min(elapsed / unit.unit, maximumCount)))\(unit.suffix)"
    }
}
