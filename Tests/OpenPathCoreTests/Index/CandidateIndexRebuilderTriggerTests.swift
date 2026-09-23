import Observation
import os
import Testing

@testable import OpenPathCore

/// 再構築の契機（起動時・手動）と、重なったときの扱い（FR-SOURCE-04、FR-CONFIG-02、DSN-002 §3）。
@MainActor
@Suite("CandidateIndexRebuilder: 再構築の契機", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderTriggerTests {
    private typealias F = RebuilderFixtures

    @Test("start で全ソースを走査し、候補をインデックスに反映する")
    func startRebuildsAllSources() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot], ghq: true))
        harness.source(.history).setSnapshot(items: [F.directory("/rebuild/history")])
        harness.source(.root(F.firstRoot)).setSnapshot(items: [F.directory("/rebuild/first/a")])
        harness.source(.root(F.secondRoot)).setSnapshot(items: [F.directory("/rebuild/second/b")])
        harness.source(.ghq).setSnapshot(items: [F.directory("/rebuild/ghq/c")])

        await harness.startAndWait()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/a", "/rebuild/ghq/c", "/rebuild/history", "/rebuild/second/b"])
    }

    @Test("start の前の rebuild では走査しない")
    func rebuildBeforeStartIsIgnored() async {
        let harness = RebuilderHarness()

        harness.rebuilder.rebuild()
        harness.rebuilder.refreshHistory()
        await harness.waitUntilIdle()

        #expect(harness.source(.history).startedCount == 0)
        #expect(harness.source(.root(F.firstRoot)).startedCount == 0)
        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("2 回目以降の start では走査し直さない")
    func startIsIdempotent() async {
        let harness = RebuilderHarness()
        await harness.startAndWait()

        harness.rebuilder.start()
        await harness.waitUntilIdle()

        #expect(harness.source(.root(F.firstRoot)).startedCount == 1)
    }

    @Test("手動の rebuild で全ソースを走査し直し、新しい候補に差し替える（FR-CONFIG-02）")
    func manualRebuildReplacesCandidates() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setSnapshot(items: [F.directory("/rebuild/first/old")])
        await harness.startAndWait()

        root.setSnapshot(items: [F.directory("/rebuild/first/new")])
        harness.rebuilder.rebuild()
        await harness.waitUntilIdle()

        #expect(root.startedCount == 2)
        #expect(harness.source(.history).startedCount == 2)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/new"])
    }

    @Test("再構築中の rebuild は重ねて走らせず、何度呼ばれても終わった後に 1 回だけ走査し直す")
    func triggersDuringRebuildAreCoalesced() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)

        harness.rebuilder.rebuild()
        harness.rebuilder.rebuild()
        harness.rebuilder.rebuild()
        #expect(root.startedCount == 1)
        root.release(items: [F.directory("/rebuild/first/first-pass")])
        await root.waitUntilStarted(count: 2)
        root.release(items: [F.directory("/rebuild/first/second-pass")])
        await harness.waitUntilIdle()

        #expect(root.startedCount == 2)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/second-pass"])
    }

    @Test("同じソースの走査は直列で、前の走査が終わるまで次を始めない")
    func sameSourceIsScannedSerially() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)

        harness.rebuilder.rebuild()
        root.release(items: [])
        await root.waitUntilStarted(count: 2)
        harness.rebuilder.rebuild()
        root.release(items: [])
        await root.waitUntilStarted(count: 3)
        root.release(items: [])
        await harness.waitUntilIdle()

        #expect(root.startedCount == 3)
        #expect(root.maxRunningCount == 1)
    }

    @Test("異なるソースは並行して走査する")
    func differentSourcesAreScannedConcurrently() async {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        let first = harness.source(.root(F.firstRoot))
        let second = harness.source(.root(F.secondRoot))
        first.setGated(true)
        second.setGated(true)

        harness.rebuilder.start()
        // どちらも解放していないまま両方が走査を始めていれば、並行している
        await first.waitUntilStarted(count: 1)
        await second.waitUntilStarted(count: 1)
        first.release(items: [])
        second.release(items: [])
        await harness.waitUntilIdle()

        #expect(first.startedCount == 1)
        #expect(second.startedCount == 1)
    }

    @Test("走査はメインスレッドの外で、優先度 utility で行う（DSN-002 §3）")
    func scansRunOffMainThreadWithUtilityPriority() async {
        let harness = RebuilderHarness()

        await harness.startAndWait()

        let root = harness.source(.root(F.firstRoot))
        #expect(root.startedCount == 1)
        #expect(!root.ranOnMainThread)
        #expect(root.priorities == [.utility])
    }

    @Test("isRebuilding は再構築の開始で true になり、後続の再構築も終わった時点で false に戻る")
    func isRebuildingTracksCycles() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setGated(true)
        #expect(!harness.rebuilder.isRebuilding)

        harness.rebuilder.start()
        #expect(harness.rebuilder.isRebuilding)
        await root.waitUntilStarted(count: 1)
        harness.rebuilder.rebuild()
        root.release(items: [])
        await root.waitUntilStarted(count: 2)
        #expect(harness.rebuilder.isRebuilding)
        root.release(items: [])
        await harness.waitUntilIdle()

        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("isRebuilding の変化を Observation で購読できる（フッターの「候補を構築中…」用）")
    func isRebuildingIsObservable() async {
        let harness = RebuilderHarness()
        let changes = ObservationRecorder()
        withObservationTracking {
            _ = harness.rebuilder.isRebuilding
        } onChange: {
            changes.record()
        }

        harness.rebuilder.start()
        await harness.waitUntilIdle()

        #expect(changes.count == 1)
    }

    @Test("refreshHistory は履歴だけを取り直し、isRebuilding を true にしない")
    func refreshHistoryRescansHistoryOnly() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        await harness.startAndWait()
        history.setGated(true)

        harness.rebuilder.refreshHistory()
        await history.waitUntilStarted(count: 2)
        #expect(!harness.rebuilder.isRebuilding)
        history.release(items: [F.directory("/rebuild/confirmed")])
        await harness.waitUntilIdle()

        #expect(harness.source(.root(F.firstRoot)).startedCount == 1)
        #expect(try await harness.indexedPaths() == ["/rebuild/confirmed"])
    }

    @Test("再構築中の refreshHistory は、終わった後に履歴だけを取り直す")
    func refreshHistoryDuringRebuildRunsAfterIt() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)

        harness.rebuilder.refreshHistory()
        root.release(items: [])
        await harness.source(.history).waitUntilStarted(count: 2)
        await harness.waitUntilIdle()

        #expect(root.startedCount == 1)
        #expect(harness.source(.history).startedCount == 2)
    }

    @Test("全件の再構築の走査中に履歴を消したら、走査を取り消して全件を走査し直し、消す前の履歴を候補に残さない")
    func historyClearDuringRebuildRestartsScan() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        let root = harness.source(.root(F.firstRoot))
        history.setSnapshot(items: [F.directory("/rebuild/cleared")])
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)
        let hasOldHistory = try await F.eventually { try await harness.indexedPaths() == ["/rebuild/cleared"] }

        history.setSnapshot(items: [])
        harness.rebuilder.historyDidClear()
        await root.waitUntilStarted(count: 2)
        // 走査し直した root を待たずに、消した後の履歴が反映される
        let isCleared = try await F.eventually { try await harness.indexedPaths().isEmpty }
        root.release(items: [F.directory("/rebuild/first/repo")])
        await harness.waitUntilIdle()

        #expect(hasOldHistory)
        #expect(isCleared)
        #expect(root.cancelledCount == 1)
        #expect(history.startedCount == 2)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/repo"])
    }

    @Test("再構築していないときに履歴を消したら、履歴だけを取り直す")
    func historyClearWhileIdleRefreshesHistoryOnly() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        history.setSnapshot(items: [F.directory("/rebuild/cleared")])
        await harness.startAndWait()

        history.setSnapshot(items: [])
        harness.rebuilder.historyDidClear()
        await harness.waitUntilIdle()

        #expect(harness.source(.root(F.firstRoot)).startedCount == 1)
        #expect(history.startedCount == 2)
        #expect(try await harness.indexedPaths().isEmpty)
    }

    @Test("同じ kind のソースが重複して渡されても、同時に走査しない")
    func duplicateKindsAreScannedOnce() async {
        let source = ScriptedCandidateSource(kind: .root(F.firstRoot))
        let index = CandidateIndex(fileExistence: RecordingFileExistenceChecker(), now: { IndexFixtures.now }, history: { [] })
        let rebuilder = CandidateIndexRebuilder(
            index: index,
            config: F.config(),
            sourceProvider: FixedSourceProvider(sources: [source, source]),
            clock: ScheduleTestClock()
        )

        rebuilder.start()
        await rebuilder.waitUntilIdle()

        #expect(source.startedCount == 1)
    }
}

/// 設定に依らず決まったソースを返す CandidateSourceProviding
private struct FixedSourceProvider: CandidateSourceProviding {
    let sources: [any CandidateSource]

    func sources(for config: Config) -> [any CandidateSource] {
        sources
    }
}

/// Observation の変更通知を数える
private final class ObservationRecorder: Sendable {
    private let changes = OSAllocatedUnfairLock(initialState: 0)

    var count: Int {
        changes.withLock { $0 }
    }

    func record() {
        changes.withLock { $0 += 1 }
    }
}
