import Testing

import OpenPathCore

/// PanelWatcher は Idle に戻ったとき、開いたままのパネルを 1 回だけ再通知（panelAppeared）する。
/// 注入に成功したパネルでは、ユーザーがパネル側で Enter（「開く」）を押せるよう、再通知でパレットを出し直さない。
@Suite("AppCoordinator: 注入後のパネル再通知とホットキー", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorReshowTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"

    /// パネルを表示して注入を成功させ、Idle に戻るまで進める。
    private static func makeHarnessAfterSuccessfulInjection() async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .succeed)
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: path, openImmediately: false))
        await harness.waitForState(.idle)
        return harness
    }

    @Test("注入に成功したパネルの再通知では、パレットを出し直さない")
    func reappearanceOfInjectedPanelIsIgnored() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterSuccess)
    }

    @Test("注入に成功した後でも、別のパネルを検知したらパレットを表示する")
    func differentPanelIsShownAfterSuccess() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()

        harness.coordinator.handle(.panelAppeared(.another))

        #expect(harness.coordinator.state == .panelShown(.another, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.another))
    }

    @Test("注入に成功したパネルが消えた後は、同じ id のパネルを検知したらパレットを表示する")
    func samePanelIsShownAfterItWasGone() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()

        harness.coordinator.handle(.panelGone)
        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.sample))
    }

    @Test("別のパネルを検知した後は、注入に成功したパネルの再通知を抑止しない")
    func suppressionIsForgottenAfterAnotherPanelAppears() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        harness.coordinator.handle(.panelAppeared(.another))
        harness.coordinator.handle(.panelGone)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.sample))
    }

    @Test("注入に成功した後、ホットキーでそのパネルのパレットを再表示できる")
    func hotkeyShowsPaletteForInjectedPanel() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(Array(harness.palette.calls.dropFirst(paletteCallsAfterSuccess.count)) == [.show(.sample)])
    }

    @Test("再通知を無視した後でも、ホットキーでそのパネルのパレットを再表示できる")
    func hotkeyShowsPaletteAfterIgnoredReappearance() async throws {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        harness.coordinator.handle(.panelAppeared(.sample))
        try #require(harness.coordinator.state == .idle)

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.sample))
    }

    @Test("ホットキーで再表示したパレットから、同じパネルへもう一度注入できる")
    func injectAgainAfterHotkeyReshow() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        harness.coordinator.handle(.hotkey)

        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: false))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.path, Self.anotherPath])
        #expect(harness.injector.calls.last == InjectorFake.Call(path: Self.anotherPath, autoConfirm: false))
    }

    @Test("注入に成功したパネルが消えた後のホットキーは、従来どおり無視する")
    func hotkeyIsIgnoredAfterInjectedPanelIsGone() async {
        let harness = await Self.makeHarnessAfterSuccessfulInjection()
        harness.coordinator.handle(.panelGone)
        let paletteCallsAfterPanelGone = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterPanelGone)
    }

    @Test("注入がタイムアウトした後は、ホットキーを従来どおり無視する（再表示は再通知に任せる）")
    func hotkeyIsIgnoredAfterTimeout() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)
        let paletteCallsAfterTimeout = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterTimeout)
    }

    @Test("injector が panelGone で失敗して Idle に戻った後は、同じパネルの再通知でパレットを表示する")
    func samePanelIsShownAfterPanelGoneError() async {
        let harness = CoordinatorHarness(injectorBehavior: .fail(InjectionError.panelGone))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.idle)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.sample))
    }

    @Test("注入に失敗して PanelShown に戻った後の同じパネルの再通知では、表示中のパレットをそのまま保つ")
    func reappearanceAfterFailureKeepsPalette() async {
        let harness = CoordinatorHarness(injectorBehavior: .fail(InjectionError.timeout(step: .waitPaste)))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))
        let paletteCallsAfterFailure = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls == paletteCallsAfterFailure)
    }
}
