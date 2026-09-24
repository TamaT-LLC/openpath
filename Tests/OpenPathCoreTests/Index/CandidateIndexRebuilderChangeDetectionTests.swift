import Testing

import OpenPathCore

/// 周期の再構築で、変更の無いソースを収集し直さない（Issue #78）。
/// 起動時・手動・設定の変更では従来どおり必ず全ソースを収集し直す。
@MainActor
@Suite("CandidateIndexRebuilder: 変更の無いソースの再構築を省く", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderChangeDetectionTests {
    private typealias F = RebuilderFixtures

    /// 起動時の再構築を終え、周期の待ちが始まった状態にする
    private static func started(_ harness: RebuilderHarness) async {
        await harness.startAndWait()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
    }

    /// 周期の期限まで時刻を進め、その再構築が終わって次の周期の待ちが始まるまで待つ。
    /// 変更が無ければソースは呼ばれないため、ソースの呼び出しではなく次の周期の待ちで終わりを見る
    private static func passPeriod(_ harness: RebuilderHarness) async {
        harness.scheduleClock.advance(by: F.interval)
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        await harness.waitUntilIdle()
    }

    /// 候補ソースに関わる設定（depth）だけを変えた設定
    private static let deeperConfig = Config(roots: [F.firstRoot], depth: Config.defaultDepth + 1, ghq: GhqConfig(enabled: false))

    @Test("周期の再構築では、変更の無いソースを収集せず、差し替えもしない")
    func periodicRebuildSkipsUnchangedSource() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        root.setSnapshot(items: [F.directory("/rebuild/first/a")])
        await Self.started(harness)

        // 変更が無いと判定されれば、収集し直す内容が変わっていても反映されない（収集していない）ことで確かめる
        root.setSnapshot(items: [F.directory("/rebuild/first/not-collected")])
        await Self.passPeriod(harness)

        #expect(root.startedCount == 1)
        #expect(root.changeCheckCount == 1)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/a"])
    }

    @Test("周期の再構築では、変更のあったソースだけを収集し直して反映する")
    func periodicRebuildCollectsOnlyChangedSources() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        let first = harness.source(.root(F.firstRoot))
        let second = harness.source(.root(F.secondRoot))
        for source in [first, second] {
            source.setTracksChanges(true)
        }
        first.setSnapshot(items: [F.directory("/rebuild/first/old")])
        second.setSnapshot(items: [F.directory("/rebuild/second/b")])
        await Self.started(harness)

        first.setSnapshot(items: [F.directory("/rebuild/first/new")])
        first.markChanged()
        await Self.passPeriod(harness)

        #expect(first.startedCount == 2)
        #expect(second.startedCount == 1)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/new", "/rebuild/second/b"])
    }

    @Test("収集し直したソースは新しい記録で次の周期を判定する")
    func markerIsRenewedAfterCollection() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        await Self.started(harness)

        root.markChanged()
        await Self.passPeriod(harness)
        await Self.passPeriod(harness)

        #expect(root.startedCount == 2)
        #expect(root.changeCheckCount == 2)
    }

    @Test("変更を確かめられないソース（記録を返さない・履歴）は周期のたびに収集する")
    func sourcesWithoutMarkerAreCollectedEveryPeriod() async {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        let untracked = harness.source(.root(F.secondRoot))
        await Self.started(harness)

        await Self.passPeriod(harness)
        await Self.passPeriod(harness)

        #expect(untracked.startedCount == 3)
        #expect(untracked.changeCheckCount == 0)
        #expect(harness.source(.history).startedCount == 3)
    }

    @Test("手動の再構築では、変更が無くても確かめずに収集し直す（FR-CONFIG-02）")
    func manualRebuildAlwaysCollects() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        await Self.started(harness)

        harness.rebuilder.rebuild()
        await harness.waitUntilIdle()

        #expect(root.startedCount == 2)
        #expect(root.changeCheckCount == 0)
    }

    @Test("候補ソースに関わる設定の変更では、変更が無くても確かめずに収集し直す")
    func configChangeAlwaysCollects() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        await Self.started(harness)

        harness.rebuilder.apply(config: Self.deeperConfig)
        await harness.waitUntilIdle()

        #expect(root.startedCount == 2)
        #expect(root.changeCheckCount == 0)
    }

    @Test("設定を変えた後の周期の再構築は、設定の変更で収集し直した時点の記録で判定する")
    func periodAfterConfigChangeUsesNewMarker() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        await Self.started(harness)
        root.markChanged()

        harness.rebuilder.apply(config: Self.deeperConfig)
        await harness.waitUntilIdle()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        await Self.passPeriod(harness)

        #expect(root.startedCount == 2)
        #expect(root.changeCheckCount == 1)
    }

    @Test("変更の確認はメインスレッドの外で行う（stat でメインスレッドを止めないため）")
    func changeCheckRunsOffMainThread() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        await Self.started(harness)

        await Self.passPeriod(harness)

        #expect(root.changeCheckCount == 1)
        #expect(!root.checkedChangesOnMainThread)
    }

    @Test("周期の再構築の間は isRebuilding が true になり、変更が無くても終われば false に戻る")
    func isRebuildingDuringPeriodicCheck() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        let history = harness.source(.history)
        root.setTracksChanges(true)
        await Self.started(harness)
        history.setGated(true)

        harness.scheduleClock.advance(by: F.interval)
        await history.waitUntilStarted(count: 2)
        #expect(harness.rebuilder.isRebuilding)
        history.release(items: [])
        await harness.waitUntilIdle()

        #expect(!harness.rebuilder.isRebuilding)
        #expect(root.startedCount == 1)
    }

    @Test("周期の再構築を取り消して走査し直すときは、取り消した収集をやり直す")
    func cancelledCollectionIsRetried() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setTracksChanges(true)
        root.setSnapshot(items: [F.directory("/rebuild/first/old")])
        await Self.started(harness)

        root.markChanged()
        root.setGated(true)
        harness.scheduleClock.advance(by: F.interval)
        await root.waitUntilStarted(count: 2)
        // 周期の再構築の途中で履歴が消されると、走査中の再構築を取り消して走査し直す
        harness.rebuilder.historyDidClear()
        await root.waitUntilStarted(count: 3)
        root.release(items: [F.directory("/rebuild/first/new")])
        await harness.waitUntilIdle()

        #expect(root.cancelledCount == 1)
        #expect(try await harness.indexedPaths() == ["/rebuild/first/new"])
    }
}
