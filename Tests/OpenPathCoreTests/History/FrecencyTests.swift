import Foundation
import Testing

import OpenPathCore

@Suite("Frecency")
struct FrecencyTests {
    struct DecayCase: Sendable, CustomTestStringConvertible {
        let elapsed: TimeInterval
        let expected: Double
        let label: String

        var testDescription: String { "\(label) → \(expected)" }
    }

    private typealias F = HistoryFixtures

    // 各区間は「未満」で判定するため、ちょうど境界の値は次の（小さい）区間に入る
    static let decayCases: [DecayCase] = [
        DecayCase(elapsed: 0, expected: 4.0, label: "0 秒"),
        DecayCase(elapsed: 30 * F.oneMinute, expected: 4.0, label: "30 分"),
        DecayCase(elapsed: F.oneHour - F.oneSecond, expected: 4.0, label: "1 時間の 1 秒前"),
        DecayCase(elapsed: F.oneHour, expected: 2.0, label: "ちょうど 1 時間"),
        DecayCase(elapsed: F.oneDay - F.oneSecond, expected: 2.0, label: "24 時間の 1 秒前"),
        DecayCase(elapsed: F.oneDay, expected: 0.5, label: "ちょうど 24 時間"),
        DecayCase(elapsed: F.oneWeek - F.oneSecond, expected: 0.5, label: "7 日の 1 秒前"),
        DecayCase(elapsed: F.oneWeek, expected: 0.25, label: "ちょうど 7 日"),
        DecayCase(elapsed: 10 * F.oneDay, expected: 0.25, label: "10 日"),
        DecayCase(elapsed: 365 * F.oneDay, expected: 0.25, label: "1 年"),
    ]

    @Test("経過時間に応じた減衰係数（境界は次の区間に入る）", arguments: decayCases)
    func decayByElapsedTime(testCase: DecayCase) {
        #expect(Frecency.decay(elapsed: testCase.elapsed) == testCase.expected)
    }

    @Test("lastUsed が未来（時計の巻き戻り）でも最大の減衰係数 4.0 として扱う")
    func decayForFutureLastUsed() {
        #expect(Frecency.decay(elapsed: -F.oneHour) == 4.0)
    }

    @Test("TST-001: 1 時間以内は decay 4.0（count 1, 30 分前 → 4.0）")
    func scoreWithinOneHour() {
        let score = Frecency.score(count: 1, lastUsed: F.ago(30 * F.oneMinute), now: F.now)

        #expect(score == 4.0)
    }

    @Test("TST-001: 1 週間超は decay 0.25（count 4, 10 日前 → 1.0）")
    func scoreOverOneWeek() {
        let score = Frecency.score(count: 4, lastUsed: F.ago(10 * F.oneDay), now: F.now)

        #expect(score == 1.0)
    }

    @Test("スコアは count に比例する")
    func scoreIsProportionalToCount() {
        let lastUsed = F.ago(2 * F.oneDay)

        let single = Frecency.score(count: 1, lastUsed: lastUsed, now: F.now)
        let triple = Frecency.score(count: 3, lastUsed: lastUsed, now: F.now)

        #expect(single == 0.5)
        #expect(triple == 1.5)
    }
}
