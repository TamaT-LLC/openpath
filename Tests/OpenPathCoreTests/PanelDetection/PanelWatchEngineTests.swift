import Testing

import OpenPathCore

@Suite("PanelWatchEngine: 副作用の実行とポーリング", .timeLimit(.minutes(1)))
@MainActor
struct PanelWatchEngineTests {
    private let finderPID = ActiveApplication.finder.processID
    private let claudePID = ActiveApplication.claude.processID
    private let interval = PanelWatchEngineHarness.pollingInterval

    @Test("開始すると最前面のアプリに張り付いて走査し、見つかったパネルを onEvent で通知する")
    func startAttachesScansAndAnnounces() async {
        let harness = PanelWatchEngineHarness()
        harness.environment.outcome = .found([.finderPanel])

        harness.engine.start(frontmost: .finder)
        await harness.waitForEvents(count: 1)

        #expect(harness.engine.isRunning)
        #expect(harness.environment.calls == [.attach(finderPID), .scan(finderPID)])
        #expect(harness.events == [.panelAppeared(.finderPanel)])
    }

    @Test("Idle の間は 200ms ごとに走査し、200ms 未満では走査しない")
    func pollsEveryInterval() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)
        await harness.drainMainActor()

        harness.clock.advance(by: interval - PanelWatchEngineHarness.smallestStep)
        await harness.drainMainActor()
        #expect(harness.environment.scanCount == 1)

        harness.clock.advance(by: PanelWatchEngineHarness.smallestStep)
        await harness.environment.waitForScans(count: 2)
        await harness.drainMainActor()

        harness.clock.advance(by: interval)
        await harness.environment.waitForScans(count: 3)
        #expect(harness.environment.scanCount == 3)
    }

    @Test("AppCoordinator が PanelShown の間はポーリングを止め、Idle に戻るとすぐに走査してポーリングを再開する")
    func pollingFollowsCoordinatorState() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)
        await harness.drainMainActor()

        harness.engine.coordinatorStateDidChange(.panelShown(.finderPanel, isPaletteVisible: true))
        harness.clock.advance(by: PanelWatchEngineHarness.severalIntervals)
        await harness.drainMainActor()
        #expect(harness.environment.scanCount == 1)

        harness.engine.coordinatorStateDidChange(.idle)
        await harness.environment.waitForScans(count: 2)
        await harness.drainMainActor()

        harness.clock.advance(by: interval)
        await harness.environment.waitForScans(count: 3)
        #expect(harness.environment.scanCount == 3)
    }

    @Test("AX 通知が届くと、ポーリングの周期を待たずに走査する")
    func axNotificationTriggersScan() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)
        await harness.drainMainActor()

        harness.engine.axNotificationDidArrive(processID: finderPID)

        await harness.environment.waitForScans(count: 2)
        #expect(harness.environment.scanCount == 2)
    }

    @Test("AXObserver を張れなかったアプリでは、PanelShown の間もポーリングを続ける")
    func keepsPollingWhilePanelShownWithoutObserver() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)
        harness.engine.axObservationDidFail(processID: finderPID)
        harness.engine.coordinatorStateDidChange(.panelShown(.finderPanel, isPaletteVisible: true))
        await harness.drainMainActor()

        harness.clock.advance(by: interval)

        await harness.environment.waitForScans(count: 2)
        #expect(harness.environment.scanCount == 2)
    }

    @Test("最前面のアプリの切り替え・終了と disabled_apps の変更に合わせて張り替える")
    func followsApplicationChanges() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)

        harness.engine.applicationDidActivate(.claude)
        await harness.environment.waitForScans(count: 2)
        harness.engine.applicationDidTerminate(processID: claudePID)
        harness.engine.applicationDidActivate(.finder)
        await harness.environment.waitForScans(count: 3)
        harness.disabledApps.bundleIdentifiers = [PanelWatchFixtures.finderBundleIdentifier]
        harness.engine.disabledAppsDidChange()

        #expect(harness.environment.calls == [
            .attach(finderPID), .scan(finderPID),
            .attach(claudePID), .scan(claudePID),
            .detach,
            .attach(finderPID), .scan(finderPID),
            .detach,
        ])
    }

    @Test("停止すると観測を外し、以降はポーリングしない")
    func stopDetachesAndStopsPolling() async {
        let harness = PanelWatchEngineHarness()
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForScans(count: 1)
        await harness.drainMainActor()

        harness.engine.stop()
        harness.clock.advance(by: PanelWatchEngineHarness.severalIntervals)
        await harness.drainMainActor()

        #expect(!harness.engine.isRunning)
        #expect(harness.environment.calls == [.attach(finderPID), .scan(finderPID), .detach])
    }

    @Test("停止後に届いた走査の結果は通知しない")
    func scanResultAfterStopIsDropped() async {
        let harness = PanelWatchEngineHarness()
        harness.environment.scanBehavior = .suspend
        harness.engine.start(frontmost: .finder)
        await harness.environment.waitForPendingScan()

        harness.engine.stop()
        harness.environment.completeScan(with: .found([.finderPanel]))
        await harness.drainMainActor()

        #expect(harness.events.isEmpty)
    }
}
