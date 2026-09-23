import Testing

import OpenPathCore

@Suite("PanelWatchPolicy: パネルの出現・消滅の通知")
struct PanelWatchPolicyNotificationTests {
    private let finderPID = ActiveApplication.finder.processID
    private let claudePID = ActiveApplication.claude.processID

    // MARK: - 出現と重複の抑止

    @Test("走査でパネルが見つかったら panelAppeared を送る")
    func detectedPanelIsAnnounced() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))

        let steps = driver.completeLatestScan(.found([.finderPanel]))

        #expect(steps == [.send(.panelAppeared(.finderPanel))])
        #expect(driver.policy.trackedPanel == .finderPanel)
    }

    @Test("パネルがなければ何も送らない")
    func noPanelSendsNothing() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))

        #expect(driver.completeLatestScan(.found([])).isEmpty)
        #expect(driver.policy.trackedPanel == nil)
    }

    @Test("同じパネルを再び見つけても、AppCoordinator の状態が変わっていなければ重複して通知しない")
    func samePanelIsNotAnnouncedTwice() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        driver.send(.pollTick)
        #expect(driver.completeLatestScan(.found([.finderPanel])).isEmpty)
        driver.send(.axNotificationReceived(processID: finderPID))
        #expect(driver.completeLatestScan(.found([.movedFinderPanel])).isEmpty)
    }

    @Test("PanelShown 中の走査で同じパネルを見つけても通知しない")
    func samePanelWhilePanelShownIsNotAnnounced() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: false)))

        driver.send(.axNotificationReceived(processID: finderPID))

        #expect(driver.completeLatestScan(.found([.finderPanel])).isEmpty)
    }

    @Test("複数のパネルが見つかったら先頭を通知し、以降は追跡中のパネルを優先する")
    func trackedPanelTakesPriorityAmongMultiplePanels() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .finder))

        #expect(driver.completeLatestScan(.found([.finderPanel, .claudePanel])) == [.send(.panelAppeared(.finderPanel))])

        driver.send(.pollTick)
        #expect(driver.completeLatestScan(.found([.claudePanel, .finderPanel])).isEmpty)
        #expect(driver.policy.trackedPanel == .finderPanel)
    }

    // MARK: - 消滅

    @Test("追跡中のパネルが消えたら panelGone を 1 回だけ送る")
    func disappearedPanelSendsPanelGoneOnce() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        driver.send(.axNotificationReceived(processID: finderPID))
        #expect(driver.completeLatestScan(.found([])) == [.send(.panelGone)])
        #expect(driver.policy.trackedPanel == nil)

        driver.send(.axNotificationReceived(processID: finderPID))
        #expect(driver.completeLatestScan(.found([])).isEmpty)
    }

    @Test("走査に失敗したら、追跡中のパネルを消えたとみなさない")
    func unavailableScanKeepsTrackedPanel() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        driver.send(.pollTick)
        #expect(driver.completeLatestScan(.unavailable).isEmpty)
        #expect(driver.policy.trackedPanel == .finderPanel)
    }

    @Test("PanelShown 中の走査に失敗しても、追跡中のパネルに panelGone を送らない")
    func unavailableScanWhilePanelShownKeepsTrackedPanel() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))
        driver.send(.axNotificationReceived(processID: finderPID))

        #expect(driver.completeLatestScan(.unavailable).isEmpty)
        #expect(driver.policy.trackedPanel == .finderPanel)
    }

    @Test("追跡中のパネルが別のパネルに置き換わったら、panelGone の後に新しいパネルの panelAppeared を送る")
    func replacedPanelSendsGoneThenAppeared() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        driver.send(.axNotificationReceived(processID: finderPID))
        let steps = driver.completeLatestScan(.found([.claudePanel]))

        #expect(steps == [.send(.panelGone), .send(.panelAppeared(.claudePanel))])
        #expect(driver.policy.trackedPanel == .claudePanel)
    }

    // MARK: - Idle に戻った後の再通知

    @Test("注入タイムアウト等で Idle に戻った後も同じパネルが開いたままなら、panelAppeared を 1 回だけ送り直す")
    func openPanelIsAnnouncedAgainAfterReturningToIdle() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))
        driver.send(.coordinatorStateChanged(.injecting(.finderPanel, path: "/tmp")))
        driver.send(.coordinatorStateChanged(.idle))

        #expect(driver.completeLatestScan(.found([.finderPanel])) == [.send(.panelAppeared(.finderPanel))])

        driver.send(.pollTick)
        #expect(driver.completeLatestScan(.found([.finderPanel])).isEmpty)
    }

    @Test("送り直す panelAppeared には最新のパネル情報（位置など）を使う")
    func reannouncementUsesLatestContext() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))
        driver.send(.coordinatorStateChanged(.idle))

        let steps = driver.completeLatestScan(.found([.movedFinderPanel]))

        #expect(steps == [.send(.panelAppeared(.movedFinderPanel))])
    }

    @Test("Idle に戻った後でも、AppCoordinator がもう一度 Idle 以外になれば送り直さない")
    func noReannouncementWhileCoordinatorIsBusyAgain() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))
        driver.send(.coordinatorStateChanged(.idle))
        driver.send(.coordinatorStateChanged(.panelShown(.claudePanel, isPaletteVisible: true)))

        #expect(driver.completeLatestScan(.found([.finderPanel])).isEmpty)
    }

    @Test("Idle に戻った後にパネルが閉じられたら panelGone を送る（タイムアウト後に残ったパレットを閉じるため）")
    func panelClosedAfterReturningToIdleSendsPanelGone() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.injecting(.finderPanel, path: "/tmp")))
        driver.send(.coordinatorStateChanged(.idle))

        #expect(driver.completeLatestScan(.found([])) == [.send(.panelGone)])
    }

    // MARK: - 張り替え・停止との関係

    @Test("パネルを追跡中に別のアプリへ切り替えると、panelGone を送ってから張り替える")
    func switchingApplicationWhileTrackingSendsPanelGoneFirst() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        let steps = driver.send(.applicationActivated(.claude))

        #expect(steps == [.send(.panelGone), .attach(claudePID), .scan(claudePID)])
        #expect(driver.policy.trackedPanel == nil)
    }

    @Test("パネルを追跡中に disabled_apps のアプリへ切り替えると、panelGone を送って観測を外す")
    func switchingToDisabledApplicationWhileTrackingSendsPanelGone() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        let steps = driver.send(.applicationActivated(.disabled))

        #expect(steps == [.send(.panelGone), .detach, .stopPolling])
    }

    @Test("パネルを追跡中に観測中のアプリが終了したら、panelGone を送って観測を外す（走査は終了を消滅とみなさないため）")
    func terminationWhileTrackingSendsPanelGone() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))

        #expect(driver.send(.applicationTerminated(processID: finderPID)) == [.send(.panelGone), .detach])
    }

    @Test("パネルを追跡中に停止すると panelGone を送る")
    func stopWhileTrackingSendsPanelGone() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        #expect(driver.send(.stop) == [.send(.panelGone), .detach, .stopPolling])
    }

    @Test("自プロセスがアクティブになっても、追跡中のパネルは消えたとみなさない")
    func ownProcessActivationKeepsTrackedPanel() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])

        #expect(driver.send(.applicationActivated(.own)).isEmpty)
        #expect(driver.policy.trackedPanel == .finderPanel)
    }

    @Test("元のアプリに戻ると、開いたままのパネルを改めて通知する")
    func returningToApplicationAnnouncesOpenPanelAgain() {
        var driver = PolicyDriver()
        driver.startWatching(.finder, initialPanels: [.finderPanel])
        driver.send(.applicationActivated(.claude))
        driver.completeLatestScan(.found([]))

        #expect(driver.send(.applicationActivated(.finder)) == [.attach(finderPID), .scan(finderPID)])
        #expect(driver.completeLatestScan(.found([.finderPanel])) == [.send(.panelAppeared(.finderPanel))])
    }
}
