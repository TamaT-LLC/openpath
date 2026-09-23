import Foundation
import Testing

import OpenPathCore

@Suite("HistoryList")
struct HistoryListTests {
    private typealias F = HistoryFixtures

    // MARK: - record

    @Test("新規パスは count 1・lastUsed = now で末尾に追加される")
    func recordAddsNewPath() {
        var list = HistoryList(entries: [HistoryEntry(path: "/a", count: 2, lastUsed: F.ago(F.oneDay))])

        list.record(path: "/b", now: F.now)

        #expect(list.entries == [
            HistoryEntry(path: "/a", count: 2, lastUsed: F.ago(F.oneDay)),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.now),
        ])
    }

    @Test("TST-001: 既存パスの record で count が 1 増え lastUsed が now に更新される")
    func recordUpdatesExistingPath() {
        var list = HistoryList(entries: [
            HistoryEntry(path: "/a", count: 3, lastUsed: F.ago(10 * F.oneDay)),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.ago(F.oneHour)),
        ])

        list.record(path: "/a", now: F.now)

        #expect(list.entry(for: "/a") == HistoryEntry(path: "/a", count: 4, lastUsed: F.now))
        #expect(list.entry(for: "/b") == HistoryEntry(path: "/b", count: 1, lastUsed: F.ago(F.oneHour)))
        #expect(list.entries.count == 2)
    }

    @Test("パスは正規化せず文字列のままキーにする")
    func recordUsesPathAsIs() {
        var list = HistoryList()

        list.record(path: "/a", now: F.now)
        list.record(path: "/a/", now: F.now)

        #expect(list.entries.map(\.path) == ["/a", "/a/"])
    }

    @Test("存在しないパスの entry(for:) は nil")
    func entryForUnknownPathIsNil() {
        #expect(HistoryList().entry(for: "/missing") == nil)
    }

    // MARK: - 初期化

    @Test("初期化時に同一パスの重複は先頭の位置に統合される（count は合算、lastUsed は新しい方）")
    func initMergesDuplicatePaths() {
        let list = HistoryList(entries: [
            HistoryEntry(path: "/a", count: 2, lastUsed: F.ago(10 * F.oneDay)),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.now),
            HistoryEntry(path: "/a", count: 3, lastUsed: F.ago(F.oneHour)),
        ])

        #expect(list.entries == [
            HistoryEntry(path: "/a", count: 5, lastUsed: F.ago(F.oneHour)),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.now),
        ])
    }

    // MARK: - frecency 降順

    @Test("frecency 降順で並ぶ")
    func sortedByFrecencyDescending() {
        let list = HistoryList(entries: [
            HistoryEntry(path: "/four", count: 1, lastUsed: F.ago(30 * F.oneMinute)), // 4.0
            HistoryEntry(path: "/two-and-half", count: 10, lastUsed: F.ago(10 * F.oneDay)), // 2.5
            HistoryEntry(path: "/six", count: 3, lastUsed: F.ago(2 * F.oneHour)), // 6.0
        ])

        let paths = list.sortedByFrecency(now: F.now).map(\.path)

        #expect(paths == ["/six", "/four", "/two-and-half"])
    }

    @Test("frecency が同点なら lastUsed が新しい順、それも同じならパスの昇順")
    func sortedByFrecencyTieBreak() {
        let list = HistoryList(entries: [
            HistoryEntry(path: "/older", count: 1, lastUsed: F.ago(3 * F.oneDay)), // 0.5
            HistoryEntry(path: "/newer", count: 1, lastUsed: F.ago(2 * F.oneDay)), // 0.5
            HistoryEntry(path: "/same-b", count: 1, lastUsed: F.ago(4 * F.oneDay)), // 0.5
            HistoryEntry(path: "/same-a", count: 1, lastUsed: F.ago(4 * F.oneDay)), // 0.5
        ])

        let paths = list.sortedByFrecency(now: F.now).map(\.path)

        #expect(paths == ["/newer", "/older", "/same-a", "/same-b"])
    }

    // MARK: - 上限

    /// frecency 5.0（count 10 × decay 0.5）のエントリを `count` 件作る。
    private static func fillerEntries(count: Int) -> [HistoryEntry] {
        (0..<count).map { index in
            HistoryEntry(path: "/filler/\(index)", count: 10, lastUsed: F.ago(2 * F.oneDay))
        }
    }

    @Test("上限は 2,000 件")
    func maxEntryCountIs2000() {
        #expect(HistoryList.maxEntryCount == 2_000)
    }

    @Test("TST-001: 2,001 件目の追加で frecency 最下位が消える")
    func recordBeyondCapacityEvictsLowestFrecency() {
        let lowest = HistoryEntry(path: "/lowest", count: 1, lastUsed: F.ago(10 * F.oneDay)) // 0.25
        var list = HistoryList(entries: Self.fillerEntries(count: HistoryList.maxEntryCount - 1) + [lowest])

        list.record(path: "/new", now: F.now)

        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: "/lowest") == nil)
        #expect(list.entry(for: "/new") != nil)
    }

    @Test("最下位が同点なら lastUsed が古い方を消す")
    func evictionTieBreakRemovesOlderLastUsed() {
        let older = HistoryEntry(path: "/older", count: 1, lastUsed: F.ago(30 * F.oneDay)) // 0.25
        let newer = HistoryEntry(path: "/newer", count: 1, lastUsed: F.ago(10 * F.oneDay)) // 0.25
        var list = HistoryList(entries: Self.fillerEntries(count: HistoryList.maxEntryCount - 2) + [older, newer])

        list.record(path: "/new", now: F.now)

        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: "/older") == nil)
        #expect(list.entry(for: "/newer") != nil)
    }

    @Test("直前に記録したパスは frecency が最下位でも消さない")
    func justRecordedPathIsNeverEvicted() {
        // 既存はすべて 5.0 で、新規（count 1 × 4.0 = 4.0）が最下位になる
        var list = HistoryList(entries: Self.fillerEntries(count: HistoryList.maxEntryCount))

        list.record(path: "/new", now: F.now)

        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: "/new") == HistoryEntry(path: "/new", count: 1, lastUsed: F.now))
    }

    @Test("上限ちょうどで既存パスを record しても何も消えない")
    func recordExistingPathAtCapacityKeepsAllEntries() {
        var list = HistoryList(entries: Self.fillerEntries(count: HistoryList.maxEntryCount))

        list.record(path: "/filler/0", now: F.now)

        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: "/filler/0")?.count == 11)
    }

    @Test("上限を超えて読み込んだ履歴は次の record で frecency 下位から上限まで削られる")
    func recordTrimsOverCapacityEntriesLoadedFromStorage() {
        let excess = 5
        let lows = (0..<excess).map { index in
            HistoryEntry(path: "/low/\(index)", count: 1, lastUsed: F.ago(10 * F.oneDay)) // 0.25
        }
        var list = HistoryList(entries: Self.fillerEntries(count: HistoryList.maxEntryCount) + lows)

        list.record(path: "/new", now: F.now)

        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: "/new") != nil)
        #expect(list.entries.allSatisfy { !$0.path.hasPrefix("/low/") })
    }
}
