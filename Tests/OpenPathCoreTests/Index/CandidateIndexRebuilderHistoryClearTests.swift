import Testing

@testable import OpenPathCore

/// 履歴のクリア（メニューの「履歴をクリア…」）を候補に反映する（Issue #92、MENU-05）。
///
/// 履歴の候補は、走査中の再構築の終わりを待たずにすぐ取り除く。消す前の履歴を読んだ収集の結果では候補を戻さない。
@MainActor
@Suite("CandidateIndexRebuilder: 履歴のクリア", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderHistoryClearTests {
    private typealias F = RebuilderFixtures

    private static let historyOnly = "/rebuild/history-only"
    private static let rootItem = "/rebuild/first/repo"
    private static let ghqRepository = "/rebuild/ghq/repo"

    /// 統合し直しに時間がかかる程度の候補数（`didRemove` を呼ぶ時点の確認用）
    private static let manyRootItemCount = 2_000

    /// 履歴を消し、`didRemove` が呼ばれるまで待つ。
    /// - Returns: `didRemove` が呼ばれた時点でクエリが使う候補の数。
    @discardableResult
    private static func clearHistory(_ harness: RebuilderHarness) async -> Int {
        let index = harness.index
        return await withCheckedContinuation { continuation in
            harness.rebuilder.historyDidClear {
                continuation.resume(returning: index.count)
            }
        }
    }

    @Test("全件の再構築の途中で履歴を消したら、取り消しを見ない遅いソースの走査を待たずに履歴の候補を取り除く")
    func clearDuringRebuildDoesNotWaitForSlowSource() async throws {
        let harness = RebuilderHarness(config: F.config(ghq: true))
        let history = harness.source(.history)
        let ghq = harness.source(.ghq)
        history.setSnapshot(items: [F.directory(Self.historyOnly)])
        // QA の再現条件（ghq の応答を 7 秒遅らせる）。取り消しても応答が返るまで終わらない遅いソース
        ghq.setGated(true)
        ghq.setHonorsCancellation(false)
        harness.rebuilder.start()
        await ghq.waitUntilStarted(count: 1)
        let hasHistory = try await F.eventually { try await harness.indexedPaths() == [Self.historyOnly] }

        history.setSnapshot(items: [])
        harness.rebuilder.historyDidClear()
        let isCleared = try await F.eventually(timeout: .seconds(1)) { try await harness.indexedPaths().isEmpty }
        let isStillBuilding = harness.rebuilder.isRebuilding
        ghq.setSnapshot(items: [F.directory(Self.ghqRepository)])
        ghq.setGated(false)
        ghq.release(items: [F.directory(Self.ghqRepository)])
        await harness.waitUntilIdle()

        #expect(hasHistory)
        #expect(isCleared)
        #expect(isStillBuilding)
        // 走査中の再構築は取り消さずに続ける（遅いソースを走査し直して構築を長引かせない）
        #expect(ghq.startedCount == 1)
        #expect(try await harness.indexedPaths() == [Self.ghqRepository])
    }

    @Test("履歴の収集が消す前の履歴を読んだ後に履歴を消しても、その収集の結果で候補を戻さない")
    func collectionStartedBeforeClearDoesNotRestoreCandidates() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        history.setGated(true)
        harness.rebuilder.start()
        await history.waitUntilStarted(count: 1)

        await Self.clearHistory(harness)
        // 消す前の履歴を読んだ収集の結果が、消した後に届く
        history.release(items: [F.directory(Self.historyOnly)])
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths().isEmpty)
        #expect(history.startedCount == 1)
    }

    @Test("再構築していないときに履歴を消したら、走査せずに履歴の候補だけをすぐ取り除く")
    func clearWhileIdleRemovesHistoryCandidatesOnly() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        let root = harness.source(.root(F.firstRoot))
        history.setSnapshot(items: [F.directory(Self.historyOnly)])
        root.setSnapshot(items: [F.directory(Self.rootItem)])
        await harness.startAndWait()

        history.setSnapshot(items: [])
        await Self.clearHistory(harness)

        // didRemove の時点で、取り除いた候補はクエリに反映されている
        #expect(try await harness.indexedPaths() == [Self.rootItem])
        await harness.waitUntilIdle()
        #expect(history.startedCount == 1)
        #expect(root.startedCount == 1)
        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("didRemove は、取り除いた候補をクエリに反映した後に呼ぶ（表示中のパレットが引き直す時点で消えている）")
    func didRemoveIsCalledAfterRemovalIsPublished() async {
        let harness = RebuilderHarness()
        let rootItems = (0..<Self.manyRootItemCount).map { F.directory("/rebuild/first/\($0)") }
        harness.source(.history).setSnapshot(items: [F.directory(Self.historyOnly)])
        harness.source(.root(F.firstRoot)).setSnapshot(items: rootItems)
        await harness.startAndWait()
        let countBeforeClear = harness.index.count

        let countAtDidRemove = await Self.clearHistory(harness)

        #expect(countBeforeClear == rootItems.count + 1)
        #expect(countAtDidRemove == rootItems.count)
    }

    @Test("続けて履歴を消しても、どちらの didRemove の時点でも取り除いた候補がクエリに反映されている")
    func repeatedClearCallsDidRemoveAfterRemovalIsPublished() async {
        let harness = RebuilderHarness()
        let rootItems = (0..<Self.manyRootItemCount).map { F.directory("/rebuild/first/\($0)") }
        harness.source(.history).setSnapshot(items: [F.directory(Self.historyOnly)])
        harness.source(.root(F.firstRoot)).setSnapshot(items: rootItems)
        await harness.startAndWait()

        // 2 回目は取り除く候補が無いが、1 回目の反映を待ってから知らせる
        let index = harness.index
        let (counts, continuation) = AsyncStream.makeStream(of: Int.self)
        harness.rebuilder.historyDidClear { continuation.yield(index.count) }
        harness.rebuilder.historyDidClear { continuation.yield(index.count) }
        var countsAtDidRemove: [Int] = []
        for await count in counts {
            countsAtDidRemove.append(count)
            if countsAtDidRemove.count == 2 { break }
        }

        #expect(countsAtDidRemove == [rootItems.count, rootItems.count])
    }

    @Test("履歴を消した後に確定した場所は、履歴の取り直しで候補に加わる")
    func historyRecordedAfterClearIsIndexed() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        history.setSnapshot(items: [F.directory(Self.historyOnly)])
        await harness.startAndWait()
        await Self.clearHistory(harness)

        history.setSnapshot(items: [F.directory("/rebuild/confirmed")])
        harness.rebuilder.refreshHistory()
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/confirmed"])
    }

    @Test("全件の再構築の途中で履歴を消しても、他のソースの走査の結果はそのまま反映する")
    func clearDuringRebuildKeepsOtherSourcesScanning() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        let root = harness.source(.root(F.firstRoot))
        history.setSnapshot(items: [F.directory(Self.historyOnly)])
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)
        let hasHistory = try await F.eventually { try await harness.indexedPaths() == [Self.historyOnly] }

        history.setSnapshot(items: [])
        await Self.clearHistory(harness)
        let pathsAfterClear = try await harness.indexedPaths()
        root.release(items: [F.directory(Self.rootItem)])
        await harness.waitUntilIdle()

        #expect(hasHistory)
        #expect(pathsAfterClear.isEmpty)
        #expect(root.cancelledCount == 0)
        #expect(root.startedCount == 1)
        #expect(try await harness.indexedPaths() == [Self.rootItem])
    }
}
