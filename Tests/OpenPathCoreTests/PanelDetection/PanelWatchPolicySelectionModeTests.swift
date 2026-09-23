import CoreGraphics
import Testing

import OpenPathCore

@Suite("PanelWatchPolicy: 選択モードの推定し直し")
struct PanelWatchPolicySelectionModeTests {
    private let finderPID = ActiveApplication.finder.processID

    /// 一覧の行を読めず、選択モードを推定し直す予定のパネル
    private static let provisionalPanel = PanelContext(
        id: PanelContext.finderPanel.id,
        isDirectoriesOnly: false,
        frame: PanelContext.finderPanel.frame,
        isSelectionModeProvisional: true
    )
    /// 推定し直した結果、フォルダのみと分かったパネル
    private static let directoriesOnlyPanel = PanelContext(
        id: PanelContext.finderPanel.id,
        isDirectoriesOnly: true,
        frame: PanelContext.finderPanel.frame
    )
    /// 推定し直しても選択モードが変わらなかった（ファイルも選べる・推定できない）パネル
    private static let settledPanel = PanelContext(
        id: PanelContext.finderPanel.id,
        isDirectoriesOnly: false,
        frame: PanelContext.finderPanel.frame
    )

    /// 推定し直す予定のパネルを検知させ、パレットを表示させた（PanelShown）状態にする。
    private func showProvisionalPanel(_ driver: inout PolicyDriver) {
        driver.startWatching(initialPanels: [Self.provisionalPanel])
        driver.send(.coordinatorStateChanged(.panelShown(Self.provisionalPanel, isPaletteVisible: true)))
    }

    @Test("選択モードを推定し直す予定のパネルを表示している間は、推定し直せるようポーリングを続ける")
    func keepsPollingWhileProvisional() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [Self.provisionalPanel])

        let steps = driver.send(.coordinatorStateChanged(.panelShown(Self.provisionalPanel, isPaletteVisible: true)))

        #expect(steps.isEmpty)
        #expect(driver.policy.isPolling)
        #expect(driver.send(.pollTick) == [.scan(finderPID)])
    }

    @Test("推定し直してフォルダのみと分かったら、変わったパネルを知らせてポーリングを止める")
    func announcesChangedSelectionMode() {
        var driver = PolicyDriver()
        showProvisionalPanel(&driver)
        driver.send(.pollTick)

        let steps = driver.completeLatestScan(.found([Self.directoriesOnlyPanel]))

        #expect(steps == [.send(.panelContextChanged(Self.directoriesOnlyPanel)), .stopPolling])
        #expect(driver.policy.trackedPanel == Self.directoriesOnlyPanel)
    }

    @Test("推定し直しても選択モードが変わらなければ、知らせずにポーリングだけ止める")
    func settlesWithoutChange() {
        var driver = PolicyDriver()
        showProvisionalPanel(&driver)
        driver.send(.pollTick)

        let steps = driver.completeLatestScan(.found([Self.settledPanel]))

        #expect(steps == [.stopPolling])
    }

    @Test("推定し直す予定の間は、推定が済むまで走査を続ける")
    func keepsPollingUntilSettled() {
        var driver = PolicyDriver()
        showProvisionalPanel(&driver)
        driver.send(.pollTick)

        let steps = driver.completeLatestScan(.found([Self.provisionalPanel]))

        #expect(steps.isEmpty)
        #expect(driver.send(.pollTick) == [.scan(finderPID)])
    }

    @Test("Idle のまま通知済みのパネルの選択モードが変わったら知らせる")
    func announcesChangeWhileIdle() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [Self.provisionalPanel])
        driver.send(.pollTick)

        let steps = driver.completeLatestScan(.found([Self.directoriesOnlyPanel]))

        #expect(steps == [.send(.panelContextChanged(Self.directoriesOnlyPanel))])
        #expect(driver.policy.isPolling)
    }

    @Test("Idle に戻って通知し直すときは、推定し直した選択モードの panelAppeared だけを送る")
    func reannouncesWithUpdatedContext() {
        var driver = PolicyDriver()
        showProvisionalPanel(&driver)
        driver.send(.coordinatorStateChanged(.idle))

        let steps = driver.completeLatestScan(.found([Self.directoriesOnlyPanel]))

        #expect(steps == [.send(.panelAppeared(Self.directoriesOnlyPanel))])
    }

    @Test("推定が済んだパネルの PanelShown 中はポーリングを止める（従来どおり）")
    func settledPanelStopsPolling() {
        var driver = PolicyDriver()
        driver.startWatching(initialPanels: [Self.settledPanel])

        #expect(driver.send(.coordinatorStateChanged(.panelShown(Self.settledPanel, isPaletteVisible: true))) == [.stopPolling])
    }
}
