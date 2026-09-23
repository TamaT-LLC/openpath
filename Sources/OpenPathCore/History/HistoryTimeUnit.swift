import Foundation

/// 履歴の時間計算に使う秒数。
/// 減衰区間や保持期間は暦（Calendar）ではなく経過秒で判定し、夏時間やタイムゾーンの影響を受けないようにする。
enum HistoryTimeUnit {
    static let secondsPerHour: TimeInterval = 60 * 60
    static let secondsPerDay: TimeInterval = 24 * secondsPerHour
    static let secondsPerWeek: TimeInterval = 7 * secondsPerDay
}
