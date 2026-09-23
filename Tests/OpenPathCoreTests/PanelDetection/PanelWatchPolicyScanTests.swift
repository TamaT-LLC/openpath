import Testing

import OpenPathCore

@Suite("PanelWatchPolicy: 補助ポーリングと走査")
struct PanelWatchPolicyScanTests {
    private let finderPID = ActiveApplication.finder.processID
    private let claudePID = ActiveApplication.claude.processID

    // MARK: - ポーリングの開始・停止

    @Test(
        "PanelShown / Injecting の間はポーリングを止める",
        arguments: [
            CoordinatorState.panelShown(.finderPanel, isPaletteVisible: true),
            CoordinatorState.panelShown(.finderPanel, isPaletteVisible: false),
            CoordinatorState.injecting(.finderPanel, path: "/tmp"),
        ]
    )
    func pollingStopsWhileCoordinatorIsBusy(state: CoordinatorState) {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.coordinatorStateChanged(state)) == [.stopPolling])
        #expect(!driver.policy.isPolling)
    }

    @Test("PanelShown から Injecting へ移っても、止めたポーリングはそのまま")
    func pollingStaysStoppedFromPanelShownToInjecting() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.coordinatorStateChanged(.injecting(.finderPanel, path: "/tmp"))).isEmpty)
    }

    @Test("Idle に戻るとポーリングを再開し、次の周期を待たずに走査する")
    func pollingResumesAndScansImmediatelyWhenIdle() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.coordinatorStateChanged(.injecting(.finderPanel, path: "/tmp")))

        let steps = driver.send(.coordinatorStateChanged(.idle))

        #expect(steps == [.startPolling, .scan(finderPID)])
        #expect(driver.policy.isPolling)
    }

    @Test("観測していない間に Idle に戻ってもポーリングしない")
    func idleWithoutAttachmentDoesNotPoll() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .disabled))
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.coordinatorStateChanged(.idle)).isEmpty)
    }

    @Test("Idle 中の周期ごとに走査する")
    func pollTickRequestsScan() {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.pollTick) == [.scan(finderPID)])
    }

    @Test("ポーリングを止めている間に届いた周期は無視する")
    func pollTickWhileNotPollingIsIgnored() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.pollTick).isEmpty)
    }

    // MARK: - AXObserver を張れなかったとき

    @Test("AXObserver を張れなかったアプリでは、PanelShown / Injecting の間もポーリングを続ける（パネルの消滅を検知するため）")
    func pollingContinuesWhileBusyWithoutObserver() {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.axObservationFailed(processID: finderPID)).isEmpty)
        #expect(driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true))).isEmpty)
        #expect(driver.send(.coordinatorStateChanged(.injecting(.finderPanel, path: "/tmp"))).isEmpty)
        #expect(driver.policy.isPolling)
        #expect(driver.send(.pollTick) == [.scan(finderPID)])
    }

    @Test("PanelShown 中に AXObserver を張れなかったと分かったら、ポーリングを再開してすぐに走査する")
    func observationFailureWhileBusyResumesPolling() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.axObservationFailed(processID: finderPID)) == [.startPolling, .scan(finderPID)])
    }

    @Test("張り替えると、AXObserver を張れなかった状態は引き継がない")
    func observationFailureIsResetOnReattach() {
        var driver = PolicyDriver()
        driver.startWatching(.finder)
        driver.send(.axObservationFailed(processID: finderPID))
        driver.send(.applicationActivated(.claude))
        driver.completeLatestScan(.found([]))

        #expect(driver.send(.coordinatorStateChanged(.panelShown(.claudePanel, isPaletteVisible: true))) == [.stopPolling])
    }

    @Test("観測していないアプリについての AXObserver の失敗は無視する")
    func observationFailureOfOtherProcessIsIgnored() {
        var driver = PolicyDriver()
        driver.startWatching(.finder)
        driver.send(.applicationActivated(.claude))
        driver.completeLatestScan(.found([]))

        #expect(driver.send(.axObservationFailed(processID: finderPID)).isEmpty)
        #expect(driver.send(.coordinatorStateChanged(.panelShown(.claudePanel, isPaletteVisible: true))) == [.stopPolling])
    }

    // MARK: - 走査の間引き

    @Test("走査中に来た周期は捨て、走査を積み上げない")
    func pollTickDuringScanIsDropped() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))

        #expect(driver.send(.pollTick).isEmpty)
        #expect(driver.completeLatestScan(.found([])).isEmpty)
    }

    @Test("走査中に届いた AX 通知は、完了後の 1 回の再走査にまとめる")
    func axNotificationsDuringScanAreCoalesced() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))

        #expect(driver.send(.axNotificationReceived(processID: finderPID)).isEmpty)
        #expect(driver.send(.axNotificationReceived(processID: finderPID)).isEmpty)
        #expect(driver.send(.pollTick).isEmpty)

        #expect(driver.completeLatestScan(.found([])) == [.scan(finderPID)])
        #expect(driver.completeLatestScan(.found([])).isEmpty)
    }

    @Test("PanelShown 中でも AX 通知が届けば走査する（パネルの消滅を検知するため）")
    func axNotificationScansWhilePanelShown() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.axNotificationReceived(processID: finderPID)) == [.scan(finderPID)])
    }

    @Test("観測していないアプリから遅れて届いた AX 通知は無視する")
    func axNotificationFromOtherProcessIsIgnored() {
        var driver = PolicyDriver()
        driver.startWatching(.finder)
        driver.send(.applicationActivated(.claude))
        driver.completeLatestScan(.found([]))

        #expect(driver.send(.axNotificationReceived(processID: finderPID)).isEmpty)
    }

    // MARK: - 古い結果の破棄

    @Test("張り替え前に依頼した走査の結果は捨てる")
    func scanResultFromPreviousAttachmentIsIgnored() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))
        driver.send(.applicationActivated(.claude))

        #expect(driver.completeOldestScan(.found([.finderPanel])).isEmpty)
        #expect(driver.policy.trackedPanel == nil)

        #expect(driver.completeLatestScan(.found([.claudePanel])) == [.send(.panelAppeared(.claudePanel))])
    }

    @Test("停止後に届いた走査の結果は捨てる")
    func scanResultAfterStopIsIgnored() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))
        driver.send(.stop)

        #expect(driver.completeLatestScan(.found([.finderPanel])).isEmpty)
        #expect(driver.policy.trackedPanel == nil)
    }

    @Test("同じ走査の結果が重ねて届いても 2 回目は捨てる")
    func duplicatedScanResultIsIgnored() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))
        guard let request = driver.pendingScans.first else {
            Issue.record("開始時に走査が依頼されていない")
            return
        }
        let result = PanelScanResult(requestID: request.id, outcome: .found([.finderPanel]))

        #expect(driver.send(.scanCompleted(result)) == [.send(.panelAppeared(.finderPanel))])
        #expect(driver.send(.scanCompleted(result)).isEmpty)
    }
}
