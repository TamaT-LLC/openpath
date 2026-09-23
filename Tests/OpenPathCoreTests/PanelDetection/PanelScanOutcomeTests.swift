import Testing

import OpenPathCore

@Suite("PanelScanOutcome: ウィンドウ一覧を取得できなかったときの走査結果")
struct PanelScanOutcomeTests {
    @Test(
        "ウィンドウがない・アプリが終了したと言い切れる場合だけ「パネルなし」とする",
        arguments: [WindowListError.noValue, .invalidElement]
    )
    func errorsMeaningNoWindowsAreTreatedAsNoPanels(error: WindowListError) {
        #expect(PanelScanOutcome(windowListError: error) == .found([]))
    }

    @Test(
        "取得できなかっただけの場合は unavailable とし、追跡中のパネルを消えたとみなさない",
        arguments: [WindowListError.attributeUnsupported, .cannotComplete, .other]
    )
    func errorsMeaningUnknownAreTreatedAsUnavailable(error: WindowListError) {
        #expect(PanelScanOutcome(windowListError: error) == .unavailable)
    }

    @Test("属性に対応していないと返されても、追跡中のパネルに panelGone を送らない")
    func attributeUnsupportedKeepsTrackedPanel() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [.finderPanel])
        driver.send(.coordinatorStateChanged(.panelShown(.finderPanel, isPaletteVisible: true)))
        driver.send(.axNotificationReceived(processID: ActiveApplication.finder.processID))

        let steps = driver.completeLatestScan(PanelScanOutcome(windowListError: .attributeUnsupported))

        #expect(steps.isEmpty)
        #expect(driver.policy.trackedPanel == .finderPanel)
    }
}
