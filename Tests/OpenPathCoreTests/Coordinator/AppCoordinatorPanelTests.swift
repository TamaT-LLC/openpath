import Testing

import OpenPathCore

@Suite("AppCoordinator: パネル検知とパレット表示", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorPanelTests {
    @Test("初期状態は Idle で、パレットには何もしない")
    func initialStateIsIdle() {
        let harness = CoordinatorHarness()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.isEmpty)
    }

    @Test("Idle で panelAppeared を受けると PanelShown になりパレットを表示する")
    func panelAppearedShowsPalette() {
        let harness = CoordinatorHarness()

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample)])
        #expect(harness.observedStates == [.panelShown(.sample, isPaletteVisible: true)])
    }

    @Test("PanelShown で panelGone を受けると Idle に戻りパレットを閉じる")
    func panelGoneFromPanelShown() {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.panelGone)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == [.show(.sample), .hide])
    }

    @Test("Esc で PanelShown のままパレットのみ非表示になり、ホットキーで再表示する")
    func escapeHidesPaletteAndHotkeyShowsItAgain() {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.escape)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.palette.calls == [.show(.sample), .hide])

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample), .hide, .show(.sample)])
    }

    @Test("Esc でパレットを閉じた後でもパネル消滅で Idle に戻る")
    func panelGoneWhilePaletteHidden() {
        let harness = CoordinatorHarness()
        harness.showPanel()
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.panelGone)

        #expect(harness.coordinator.state == .idle)
    }

    @Test("Idle 中のホットキーは無視する（状態もパレットも変えない）")
    func hotkeyIsIgnoredWhileIdle() {
        let harness = CoordinatorHarness()

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.isEmpty)
        #expect(harness.observedStates.isEmpty)
    }

    @Test("パレット表示中のホットキーでは何もしない")
    func hotkeyWhilePaletteVisibleDoesNothing() {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample)])
    }

    @Test("パレット非表示中の Esc では何もしない")
    func escapeWhilePaletteHiddenDoesNothing() {
        let harness = CoordinatorHarness()
        harness.showPanel()
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.escape)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.palette.calls == [.show(.sample), .hide])
    }

    @Test("同じパネルの再検知ではパレットを出し直さない（Esc で閉じた状態を保つ）")
    func reappearanceOfSamePanelIsIgnored() {
        let harness = CoordinatorHarness()
        harness.showPanel()
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.palette.calls == [.show(.sample), .hide])
    }

    @Test("別のパネルを検知したら、そのパネルに合わせてパレットを表示し直す")
    func differentPanelReplacesCurrentPanel() {
        let harness = CoordinatorHarness()
        harness.showPanel(.sample)
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.panelAppeared(.another))

        #expect(harness.coordinator.state == .panelShown(.another, isPaletteVisible: true))
        #expect(harness.palette.calls == [.show(.sample), .hide, .show(.another)])
    }

    @Test("Idle 中の confirm は無視する")
    func confirmIsIgnoredWhileIdle() async {
        let harness = CoordinatorHarness()

        harness.coordinator.handle(.confirm(path: "/tmp/a", openImmediately: false))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.injector.calls.isEmpty)
        #expect(harness.palette.calls.isEmpty)
    }

    @Test("パレット非表示中の confirm は無視する")
    func confirmIsIgnoredWhilePaletteHidden() async {
        let harness = CoordinatorHarness()
        harness.showPanel()
        harness.coordinator.handle(.escape)

        harness.coordinator.handle(.confirm(path: "/tmp/a", openImmediately: false))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.injector.calls.isEmpty)
    }
}
