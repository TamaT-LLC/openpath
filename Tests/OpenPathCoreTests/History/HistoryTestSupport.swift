import Foundation

import OpenPathCore

/// History 系テストで共有する固定時刻と時間単位。
/// 実行時刻に依存させないため、すべてのテストはこの基準時刻からの相対で日時を作る。
enum HistoryFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static let oneSecond: TimeInterval = 1
    static let oneMinute: TimeInterval = 60
    static let oneHour: TimeInterval = 60 * oneMinute
    static let oneDay: TimeInterval = 24 * oneHour
    static let oneWeek: TimeInterval = 7 * oneDay

    /// 基準時刻から `interval` 秒前の日時。
    static func ago(_ interval: TimeInterval) -> Date {
        now.addingTimeInterval(-interval)
    }
}

/// 指定したパスだけが存在するとみなすファイル存在確認のスタブ。
struct StubFileExistenceChecker: FileExistenceChecking {
    let existingPaths: Set<String>

    init(existingPaths: Set<String> = []) {
        self.existingPaths = existingPaths
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }
}
