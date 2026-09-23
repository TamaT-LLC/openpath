import Testing

import OpenPathCore

/// 走査結果の差し替え（TST-001 §2.4「アトミック差し替え」、UX-001 §5「履歴分は即時表示」）とキャンセル・警告。
@MainActor
@Suite("CandidateIndexRebuilder: 差し替えとキャンセル", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderReplaceTests {
    private typealias F = RebuilderFixtures

    private struct UnexpectedSourceError: Error {}

    @Test("走査中に query しても旧結果が返り、走査を終えると新しい結果に差し替わる（TST-001 §2.4）")
    func queryDuringScanReturnsPreviousCandidates() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setSnapshot(items: [F.directory("/rebuild/first/old-a"), F.directory("/rebuild/first/old-b")])
        await harness.startAndWait()
        root.setGated(true)

        harness.rebuilder.rebuild()
        await root.waitUntilStarted(count: 2)

        #expect(harness.rebuilder.isRebuilding)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/old-a", "/rebuild/first/old-b"])
        root.release(items: [F.directory("/rebuild/first/new")])
        await harness.waitUntilIdle()
        #expect(try await harness.indexedPaths() == ["/rebuild/first/new"])
    }

    @Test("履歴は roots の走査を待たずに反映され、再構築中でもすぐに返る（UX-001 §5）")
    func historyIsAvailableWhileRootsAreScanning() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        harness.source(.history).setSnapshot(items: [F.directory("/rebuild/history")])
        root.setGated(true)

        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)

        let isHistoryIndexed = await F.eventually { harness.index.count == 1 }
        #expect(isHistoryIndexed)
        #expect(harness.rebuilder.isRebuilding)
        #expect(try await harness.indexedPaths() == ["/rebuild/history"])
        root.release(items: [F.directory("/rebuild/first/a")])
        await harness.waitUntilIdle()
        #expect(try await harness.indexedPaths() == ["/rebuild/first/a", "/rebuild/history"])
    }

    @Test("stop で走査を取り消し、取り消した走査の結果では差し替えない")
    func stopCancelsScanWithoutReplacing() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setSnapshot(items: [F.directory("/rebuild/first/old")])
        await harness.startAndWait()
        root.setGated(true)
        harness.rebuilder.rebuild()
        await root.waitUntilStarted(count: 2)

        harness.rebuilder.stop()
        #expect(!harness.rebuilder.isRebuilding)
        await harness.waitUntilIdle()

        #expect(root.cancelledCount == 1)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/old"])
    }

    @Test("キャンセルを見ずに結果を返したソースでも、キャンセル後の結果では差し替えない")
    func resultAfterCancellationIsDiscarded() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setSnapshot(items: [F.directory("/rebuild/first/old")])
        await harness.startAndWait()
        root.setGated(true)
        root.setHonorsCancellation(false)
        harness.rebuilder.rebuild()
        await root.waitUntilStarted(count: 2)

        harness.rebuilder.stop()
        root.release(items: [F.directory("/rebuild/first/late")])
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/old"])
    }

    @Test("キャンセル以外のエラーを投げたソースは差し替えず、他のソースは差し替える")
    func unexpectedErrorKeepsPreviousCandidates() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        let first = harness.source(.root(F.firstRoot))
        let second = harness.source(.root(F.secondRoot))
        first.setSnapshot(items: [F.directory("/rebuild/first/old")])
        await harness.startAndWait()

        first.setFailure(UnexpectedSourceError())
        second.setSnapshot(items: [F.directory("/rebuild/second/new")])
        harness.rebuilder.rebuild()
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/old", "/rebuild/second/new"])
        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("各ソースの直近の警告をソースの並び順で公開する")
    func publishesLatestWarnings() async {
        let rootWarning = CandidateSourceWarning.rootUnavailable(root: F.secondRoot, reason: .notFound)
        let ghqWarning = CandidateSourceWarning.ghqFailed(.timedOut(.list))
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot], ghq: true))
        harness.source(.ghq).setSnapshot(items: [], warnings: [ghqWarning])
        harness.source(.root(F.secondRoot)).setSnapshot(items: [], warnings: [rootWarning])

        await harness.startAndWait()

        #expect(harness.rebuilder.warnings == [rootWarning, ghqWarning])
    }

    @Test("警告の解消と、ソースを外したときに警告を消す")
    func clearsResolvedAndRemovedWarnings() async {
        let rootWarning = CandidateSourceWarning.rootTruncated(root: F.firstRoot, limit: RootScanOptions.defaultItemLimit)
        let ghqWarning = CandidateSourceWarning.ghqFailed(.emptyRoot)
        let harness = RebuilderHarness(config: F.config(ghq: true))
        harness.source(.root(F.firstRoot)).setSnapshot(items: [], warnings: [rootWarning])
        harness.source(.ghq).setSnapshot(items: [], warnings: [ghqWarning])
        await harness.startAndWait()
        #expect(harness.rebuilder.warnings == [rootWarning, ghqWarning])

        harness.source(.root(F.firstRoot)).setSnapshot(items: [])
        harness.rebuilder.apply(config: F.config(ghq: false))
        await harness.waitUntilIdle()

        #expect(harness.rebuilder.warnings.isEmpty)
    }

    @Test("取り消した走査のソースは直前の警告を保つ")
    func cancelledSourceKeepsPreviousWarnings() async {
        let rootWarning = CandidateSourceWarning.rootUnavailable(root: F.firstRoot, reason: .unreadable)
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setSnapshot(items: [], warnings: [rootWarning])
        await harness.startAndWait()
        root.setGated(true)
        harness.rebuilder.rebuild()
        await root.waitUntilStarted(count: 2)

        harness.rebuilder.stop()
        await harness.waitUntilIdle()

        #expect(harness.rebuilder.warnings == [rootWarning])
    }
}
