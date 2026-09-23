import Testing

import OpenPathCore

/// #27 で想定する配線（onEvent → AppCoordinator.handle、onStateChange → coordinatorStateDidChange）での振る舞い。
@Suite("PanelWatchEngine: AppCoordinator との連携", .timeLimit(.minutes(1)))
@MainActor
struct PanelWatchEngineCoordinatorTests {
    private let finderPID = ActiveApplication.finder.processID
    private let panelShown = CoordinatorState.panelShown(.finderPanel, isPaletteVisible: true)

    @Test("パネルを検知するとパレットを表示し、PanelShown の間はポーリングを止める")
    func detectedPanelShowsPaletteAndPausesPolling() async {
        let watcher = PanelWatchEngineHarness()
        let coordinator = CoordinatorHarness()
        watcher.connect(to: coordinator)
        watcher.environment.outcome = .found([.finderPanel])

        watcher.engine.start(frontmost: .finder)
        await coordinator.waitForState(panelShown)
        await watcher.drainMainActor()
        watcher.clock.advance(by: PanelWatchEngineHarness.severalIntervals)
        await watcher.drainMainActor()

        #expect(coordinator.palette.calls == [.show(.finderPanel)])
        #expect(watcher.environment.scanCount == 1)
        #expect(watcher.events == [.panelAppeared(.finderPanel)])
    }

    @Test("注入タイムアウトで Idle に戻ると、開いたままのパネルを再検知してパレットを出し直す")
    func reannouncesOpenPanelAfterInjectionTimeout() async {
        let watcher = PanelWatchEngineHarness()
        let coordinator = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        watcher.connect(to: coordinator)
        watcher.environment.outcome = .found([.finderPanel])
        watcher.engine.start(frontmost: .finder)
        await coordinator.waitForState(panelShown)

        coordinator.coordinator.handle(.confirm(path: "/tmp/repo", openImmediately: false))
        await coordinator.injector.waitUntilCalled()
        coordinator.clock.advance(by: AppCoordinator.injectionTimeout)
        await coordinator.waitForState(panelShown)

        #expect(coordinator.observedStates == [
            panelShown,
            .injecting(.finderPanel, path: "/tmp/repo"),
            .idle,
            panelShown,
        ])
        #expect(coordinator.palette.calls.last == .show(.finderPanel))
        #expect(watcher.events == [.panelAppeared(.finderPanel), .panelAppeared(.finderPanel)])
    }

    @Test("パネルが閉じられたら panelGone で Idle に戻り、パレットを閉じる")
    func closedPanelHidesPalette() async {
        let watcher = PanelWatchEngineHarness()
        let coordinator = CoordinatorHarness()
        watcher.connect(to: coordinator)
        watcher.environment.outcome = .found([.finderPanel])
        watcher.engine.start(frontmost: .finder)
        await coordinator.waitForState(panelShown)

        watcher.environment.outcome = .found([])
        watcher.engine.axNotificationDidArrive(processID: finderPID)
        await coordinator.waitForState(.idle)

        #expect(coordinator.palette.calls == [.show(.finderPanel), .hide])
        #expect(watcher.events == [.panelAppeared(.finderPanel), .panelGone])
    }
}
