import Foundation
import Testing

import OpenPathCore

@Suite("RelativeDateFormatter")
struct RelativeDateFormatterTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static let second: TimeInterval = 1
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour

    @Test("履歴がない（最終使用日時が nil）場合は空欄")
    func nilIsBlank() {
        #expect(RelativeDateFormatter.string(from: nil, relativeTo: Self.now).isEmpty)
    }

    @Test(
        "経過時間を最も大きい単位の切り捨てで表す",
        arguments: [
            (elapsed: 0, expected: "たった今"),
            (elapsed: 59 * second, expected: "たった今"),
            (elapsed: minute, expected: "1分前"),
            (elapsed: 3 * minute + 59 * second, expected: "3分前"),
            (elapsed: hour - second, expected: "59分前"),
            (elapsed: hour, expected: "1時間前"),
            (elapsed: day - second, expected: "23時間前"),
            (elapsed: day, expected: "1日前"),
            (elapsed: 2 * day, expected: "2日前"),
            (elapsed: 7 * day - second, expected: "6日前"),
            (elapsed: 7 * day, expected: "1週間前"),
            (elapsed: 21 * day, expected: "3週間前"),
            (elapsed: 30 * day - second, expected: "4週間前"),
            (elapsed: 30 * day, expected: "1か月前"),
            (elapsed: 364 * day, expected: "12か月前"),
            (elapsed: 365 * day, expected: "1年前"),
            (elapsed: 800 * day, expected: "2年前"),
        ] as [(elapsed: TimeInterval, expected: String)]
    )
    func formatsElapsedTime(elapsed: TimeInterval, expected: String) {
        let date = Self.now.addingTimeInterval(-elapsed)

        #expect(RelativeDateFormatter.string(from: date, relativeTo: Self.now) == expected)
    }

    @Test("未来の日時（時計のずれ等）は「たった今」とする")
    func futureDateIsJustNow() {
        let future = Self.now.addingTimeInterval(Self.hour)

        #expect(RelativeDateFormatter.string(from: future, relativeTo: Self.now) == "たった今")
    }

    @Test("壊れた履歴などで極端に古い日時が来ても落ちず、上限の年数で表す")
    func extremelyOldDateIsCapped() {
        let extremelyOld = Date(timeIntervalSinceReferenceDate: -1e300)

        #expect(RelativeDateFormatter.string(from: extremelyOld, relativeTo: Self.now) == "9999年前")
    }
}
