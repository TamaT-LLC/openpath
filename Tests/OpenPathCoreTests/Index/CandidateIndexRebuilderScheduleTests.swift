import Testing

import OpenPathCore

/// 一定間隔の再構築（FR-SOURCE-04「既定 5 分」、DSN-002 §3）。仮想の時計で検証する。
@MainActor
@Suite("CandidateIndexRebuilder: 5 分間隔の再構築", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderScheduleTests {
    private typealias F = RebuilderFixtures

    @Test("既定の間隔は 5 分")
    func defaultIntervalIsFiveMinutes() {
        #expect(CandidateIndexRebuilder.defaultInterval == .seconds(5 * 60))
    }

    @Test("再構築を終えてから 5 分ごとに走査し直す")
    func rebuildsEveryInterval() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        await harness.startAndWait()

        for pass in 2...3 {
            await harness.scheduleClock.waitUntilSleeping(count: 1)
            harness.scheduleClock.advance(by: F.interval - F.tick)
            #expect(harness.scheduleClock.sleeperCount == 1)
            #expect(root.startedCount == pass - 1)

            harness.scheduleClock.advance(by: F.tick)
            await root.waitUntilStarted(count: pass)
            await harness.waitUntilIdle()
        }

        #expect(root.startedCount == 3)
        #expect(harness.source(.history).startedCount == 3)
    }

    @Test("周期の待ちは再構築を終えた時点から数え、走査中には次の周期を積まない")
    func intervalStartsAfterRebuildFinishes() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)

        // MainActor に積まれた処理を先に進めてから、走査中は周期の待ちが始まっていないことを確かめる
        await Task.yield()
        #expect(harness.scheduleClock.sleeperCount == 0)
        // 走査に 5 分以上かかっても、その間に周期の再構築を積まない
        harness.scheduleClock.advance(by: F.interval + F.interval)
        root.release(items: [])
        await harness.waitUntilIdle()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        harness.scheduleClock.advance(by: F.interval - F.tick)

        #expect(root.startedCount == 1)
        #expect(harness.scheduleClock.sleeperCount == 1)
    }

    @Test("手動の rebuild の後は、そこから 5 分数え直す")
    func manualRebuildResetsInterval() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        await harness.startAndWait()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        let half = F.interval / 2

        harness.scheduleClock.advance(by: half)
        harness.rebuilder.rebuild()
        await harness.waitUntilIdle()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        // 起動時の再構築から 5 分を過ぎても、手動の再構築から 5 分経つまでは走査しない
        harness.scheduleClock.advance(by: F.interval - F.tick)
        #expect(root.startedCount == 2)
        #expect(harness.scheduleClock.sleeperCount == 1)

        harness.scheduleClock.advance(by: F.tick)
        await root.waitUntilStarted(count: 3)
        await harness.waitUntilIdle()

        #expect(root.startedCount == 3)
    }

    @Test("履歴だけの取り直しでは数え直さない（確定が 5 分より短い間隔で続いても、周期どおりに走査し直す）")
    func refreshHistoryDoesNotResetInterval() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        await harness.startAndWait()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        let half = F.interval / 2

        harness.scheduleClock.advance(by: half)
        harness.rebuilder.refreshHistory()
        await harness.source(.history).waitUntilStarted(count: 2)
        await harness.waitUntilIdle()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        harness.scheduleClock.advance(by: F.interval - half)

        // 起動時の再構築を終えてから 5 分で周期の待ちが明ける
        try #require(harness.scheduleClock.sleeperCount == 0)
        await root.waitUntilStarted(count: 2)
        await harness.waitUntilIdle()
        #expect(root.startedCount == 2)
    }

    @Test("履歴の取り直し中に周期の期限が来たら、取り直しを終えた後に全件を走査し直し、周期を数え直す")
    func periodDueDuringHistoryRefreshRebuildsAfterIt() async throws {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        let history = harness.source(.history)
        await harness.startAndWait()
        await harness.scheduleClock.waitUntilSleeping(count: 1)
        history.setGated(true)
        harness.rebuilder.refreshHistory()
        await history.waitUntilStarted(count: 2)

        harness.scheduleClock.advance(by: F.interval)
        try #require(await F.eventually { harness.rebuilder.isRebuilding })
        history.release(items: [])
        await history.waitUntilStarted(count: 3)
        history.release(items: [])
        await harness.waitUntilIdle()
        await harness.scheduleClock.waitUntilSleeping(count: 1)

        #expect(root.startedCount == 2)
        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("stop の後は周期の再構築を行わない")
    func stopCancelsSchedule() async {
        let harness = RebuilderHarness()
        let root = harness.source(.root(F.firstRoot))
        await harness.startAndWait()
        await harness.scheduleClock.waitUntilSleeping(count: 1)

        harness.rebuilder.stop()
        #expect(await F.eventually { harness.scheduleClock.sleeperCount == 0 })
        harness.scheduleClock.advance(by: F.interval)
        await harness.waitUntilIdle()

        #expect(root.startedCount == 1)
    }

    @Test("間隔は注入できる")
    func intervalIsInjectable() async {
        let customInterval: Duration = .seconds(30)
        let scheduleClock = ScheduleTestClock()
        let root = ScriptedCandidateSource(kind: .root(F.firstRoot))
        let index = CandidateIndex(fileExistence: RecordingFileExistenceChecker(), now: { IndexFixtures.now }, history: { [] })
        let rebuilder = CandidateIndexRebuilder(
            index: index,
            config: F.config(),
            sourceProvider: SingleSourceProvider(source: root),
            interval: customInterval,
            clock: scheduleClock
        )
        rebuilder.start()
        await root.waitUntilStarted(count: 1)
        await scheduleClock.waitUntilSleeping(count: 1)

        scheduleClock.advance(by: customInterval)
        await root.waitUntilStarted(count: 2)
        rebuilder.stop()

        #expect(root.startedCount == 2)
    }
}

/// 設定に依らず 1 つのソースだけを返す CandidateSourceProviding
private struct SingleSourceProvider: CandidateSourceProviding {
    let source: any CandidateSource

    func sources(for config: Config) -> [any CandidateSource] {
        [source]
    }
}
