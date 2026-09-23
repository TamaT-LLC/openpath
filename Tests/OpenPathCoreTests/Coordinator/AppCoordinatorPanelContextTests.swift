import Testing

import OpenPathCore

@Suite("AppCoordinator: パネルの情報の更新", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorPanelContextTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"

    /// .sample と同じパネルで、選択モードを推定し直した結果フォルダのみと分かったもの
    private static let updated = PanelContext(
        id: PanelContext.sample.id,
        isDirectoriesOnly: true,
        frame: PanelContext.sample.frame
    )

    @Test("パレットの表示中は状態のパネルを差し替え、パレットにも知らせる")
    func updatesVisiblePalette() {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.panelContextChanged(Self.updated))

        #expect(harness.coordinator.state == .panelShown(Self.updated, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample), .update(Self.updated)])
    }

    @Test("Esc でパレットだけ閉じている間は状態だけ差し替え、ホットキーでの再表示に使う")
    func updatesHiddenPaletteOnReshow() {
        let harness = CoordinatorHarness()
        harness.showPanel()
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.panelContextChanged(Self.updated))
        let callsBeforeReshow = harness.palette.calls
        harness.coordinator.handle(.hotkey)

        #expect(callsBeforeReshow == [.show(.sample), .hide])
        #expect(harness.palette.calls.last == .show(Self.updated))
    }

    @Test("追跡中でないパネルの更新は無視する")
    func ignoresOtherPanel() {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.panelContextChanged(.another))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample)])
    }

    @Test("注入中は状態だけ差し替え、失敗して PanelShown に戻るときに使う")
    func updatesDuringInjection() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))

        harness.coordinator.handle(.panelContextChanged(Self.updated))
        let stateWhileInjecting = harness.coordinator.state
        await harness.injector.waitUntilCalled()
        harness.injector.resume(with: .failure(InjectionError.targetNotFrontmost))
        await harness.waitForState(.panelShown(Self.updated, isPaletteVisible: true))

        #expect(stateWhileInjecting == .injecting(Self.updated, path: Self.path))
        #expect(!harness.palette.calls.contains(.update(Self.updated)))
    }

    @Test("注入に成功したパネルの更新は、ホットキーでの再表示に使う")
    func updatesInjectedPanel() async {
        let harness = CoordinatorHarness(injectorBehavior: .succeed)
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.idle)

        harness.coordinator.handle(.panelContextChanged(Self.updated))
        harness.coordinator.handle(.hotkey)

        #expect(harness.palette.calls.last == .show(Self.updated))
    }

    @Test("パネルを追跡していない Idle では無視する")
    func ignoresWhileIdle() {
        let harness = CoordinatorHarness()

        harness.coordinator.handle(.panelContextChanged(Self.updated))

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.isEmpty)
    }
}
