import Foundation
import Testing

import OpenPathCore

@Suite("HistoryList の掃除")
struct HistoryPruneTests {
    private typealias F = HistoryFixtures

    private static let staleDays = 90.0

    /// 呼ばれたらテスト失敗とする存在確認。不要な経路でファイルシステムに触れないことを検証する。
    private struct UnexpectedFileExistenceChecker: FileExistenceChecking {
        func fileExists(atPath path: String) -> Bool {
            Issue.record("\(path) の存在確認は不要")
            return true
        }
    }

    @Test("保持期間は 90 日")
    func staleThresholdIs90Days() {
        #expect(HistoryList.staleThreshold == Self.staleDays * F.oneDay)
    }

    @Test("TST-001: 90 日以上未使用かつ存在しないエントリは削除される")
    func prunesStaleAndMissingEntry() {
        let list = HistoryList(entries: [
            HistoryEntry(path: "/gone", count: 50, lastUsed: F.ago(100 * F.oneDay)),
            HistoryEntry(path: "/recent", count: 1, lastUsed: F.ago(F.oneHour)),
        ])

        let pruned = list.pruned(now: F.now, fileExistence: StubFileExistenceChecker(existingPaths: ["/recent"]))

        #expect(pruned.entries == [HistoryEntry(path: "/recent", count: 1, lastUsed: F.ago(F.oneHour))])
    }

    @Test("90 日以上未使用でも存在すれば残る")
    func keepsStaleEntryThatStillExists() {
        let stale = HistoryEntry(path: "/still-here", count: 1, lastUsed: F.ago(365 * F.oneDay))
        let list = HistoryList(entries: [stale])

        let pruned = list.pruned(now: F.now, fileExistence: StubFileExistenceChecker(existingPaths: ["/still-here"]))

        #expect(pruned.entries == [stale])
    }

    @Test("存在しなくても 90 日未満なら残る")
    func keepsMissingEntryUsedWithin90Days() {
        let missing = HistoryEntry(path: "/unmounted", count: 1, lastUsed: F.ago(89 * F.oneDay))
        let list = HistoryList(entries: [missing])

        let pruned = list.pruned(now: F.now, fileExistence: StubFileExistenceChecker())

        #expect(pruned.entries == [missing])
    }

    @Test("ちょうど 90 日は削除対象、1 秒足りなければ残る")
    func staleThresholdBoundary() {
        let threshold = Self.staleDays * F.oneDay
        let list = HistoryList(entries: [
            HistoryEntry(path: "/exactly-90-days", count: 1, lastUsed: F.ago(threshold)),
            HistoryEntry(path: "/just-under-90-days", count: 1, lastUsed: F.ago(threshold - F.oneSecond)),
        ])

        let pruned = list.pruned(now: F.now, fileExistence: StubFileExistenceChecker())

        #expect(pruned.entries.map(\.path) == ["/just-under-90-days"])
    }

    @Test("残ったエントリの順序と内容は変わらない")
    func preservesOrderOfRemainingEntries() {
        let entries = [
            HistoryEntry(path: "/c", count: 3, lastUsed: F.ago(F.oneDay)),
            HistoryEntry(path: "/gone", count: 1, lastUsed: F.ago(200 * F.oneDay)),
            HistoryEntry(path: "/a", count: 1, lastUsed: F.ago(F.oneWeek)),
            HistoryEntry(path: "/b", count: 9, lastUsed: F.ago(120 * F.oneDay)),
        ]
        let list = HistoryList(entries: entries)

        let pruned = list.pruned(now: F.now, fileExistence: StubFileExistenceChecker(existingPaths: ["/b"]))

        #expect(pruned.entries == [entries[0], entries[2], entries[3]])
    }

    @Test("90 日未満のエントリは存在確認をしない")
    func doesNotCheckExistenceOfRecentEntries() {
        let list = HistoryList(entries: [
            HistoryEntry(path: "/recent", count: 1, lastUsed: F.ago(F.oneDay)),
            HistoryEntry(path: "/month-ago", count: 1, lastUsed: F.ago(30 * F.oneDay)),
        ])

        let pruned = list.pruned(now: F.now, fileExistence: UnexpectedFileExistenceChecker())

        #expect(pruned == list)
    }
}

@Suite("LocalFileExistenceChecker")
struct LocalFileExistenceCheckerTests {
    private let checker = LocalFileExistenceChecker()

    @Test("実在するディレクトリとファイルは存在する")
    func existingPaths() {
        #expect(checker.fileExists(atPath: PackageLayout.rootDirectory.path))
        #expect(checker.fileExists(atPath: PackageLayout.url("Package.swift").path))
    }

    @Test("存在しないパスは存在しない")
    func missingPath() {
        let missing = PackageLayout.url("no-such-file-\(UUID().uuidString)")

        #expect(checker.fileExists(atPath: missing.path) == false)
    }
}
