import Testing

import OpenPathCore

@Suite("AppCoordinator: 注入タイムアウトとパネル消滅", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorCancellationTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"
    private static let justBeforeTimeout = Duration.milliseconds(1)

    /// PanelShown から confirm して、注入が始まるまで進める。
    private static func makeInjectingHarness(respondsToCancellation: Bool = true) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: respondsToCancellation))
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: path, openImmediately: false))
        await harness.injector.waitUntilCalled()
        return harness
    }

    @Test("注入のタイムアウトは 1.5 秒")
    func injectionTimeoutIsOneAndAHalfSeconds() {
        #expect(AppCoordinator.injectionTimeout == .milliseconds(1500))
    }

    @Test("注入が 1.5 秒以内に終わらなければ Idle に戻り、エラーをパレットに渡して注入を止める")
    func injectionTimesOut() async throws {
        let expectedMessage = try #require(InjectionError.timeout(step: .overall).userMessage)
        let harness = await Self.makeInjectingHarness()

        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)

        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .showError(expectedMessage)])
        // エラーを読めるようにパレットは閉じない
        #expect(!harness.palette.calls.contains(.hide))
        #expect(harness.history.recordedPaths.isEmpty)
        await harness.injector.waitForCancellation()
        #expect(harness.injector.isCancelled)
    }

    @Test("1.5 秒に達するまではタイムアウトしない")
    func doesNotTimeOutBeforeDeadline() async {
        let harness = await Self.makeInjectingHarness()

        harness.clock.advance(by: AppCoordinator.injectionTimeout - Self.justBeforeTimeout)
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))

        harness.clock.advance(by: Self.justBeforeTimeout)
        await harness.waitForState(.idle)
    }

    @Test("注入が成功した後は、期限が来てもタイムアウトを発火しない")
    func timeoutIsCancelledAfterSuccess() async {
        let harness = CoordinatorHarness(injectorBehavior: .succeed)
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.idle)
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterSuccess)
    }

    @Test("Injecting 中にパネルが消えると Idle に戻り、パレットを閉じて注入をキャンセルする")
    func panelGoneWhileInjecting() async {
        let harness = await Self.makeInjectingHarness()

        harness.coordinator.handle(.panelGone)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .hide])
        await harness.injector.waitForCancellation()
        await harness.drainMainActor()
        // キャンセルされた注入の結果で状態・履歴が変わらない
        #expect(harness.coordinator.state == .idle)
        #expect(harness.history.recordedPaths.isEmpty)
        #expect(!harness.palette.calls.contains { if case .showError = $0 { true } else { false } })
    }

    @Test("confirm 直後（注入開始前）にパネルが消えた場合は注入を始めない")
    func panelGoneBeforeInjectionStarts() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))

        harness.coordinator.handle(.panelGone)
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.injector.calls.isEmpty)
    }

    @Test("パネル消滅後に遅れて届いた注入成功は無視し、次のパネルの状態を壊さない")
    func lateSuccessAfterPanelGoneIsIgnored() async {
        let harness = await Self.makeInjectingHarness(respondsToCancellation: false)
        harness.coordinator.handle(.panelGone)
        harness.showPanel(.another)

        harness.injector.resume(with: .success(()))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .panelShown(.another, isPaletteVisible: true))
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("古い注入の結果が遅れて届いても、実行中の新しい注入の完了と取り違えない")
    func lateResultIsNotMistakenForCurrentInjection() async {
        let harness = await Self.makeInjectingHarness(respondsToCancellation: false)
        harness.coordinator.handle(.panelGone)
        harness.showPanel(.another)
        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)

        harness.injector.resume(callAt: 0, with: .success(()))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .injecting(.another, path: Self.anotherPath))
        #expect(harness.history.recordedPaths.isEmpty)

        harness.injector.resume(callAt: 1, with: .success(()))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.anotherPath])
    }

    @Test("タイムアウト後に遅れて届いた注入成功は履歴に記録しない")
    func lateSuccessAfterTimeoutIsIgnored() async {
        let harness = await Self.makeInjectingHarness(respondsToCancellation: false)
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)

        harness.injector.resume(with: .success(()))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("タイムアウト後にエラー表示で残ったパレットは Esc で閉じられる")
    func escapeClosesPaletteLeftAfterTimeout() async {
        let harness = await Self.makeInjectingHarness()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)

        harness.coordinator.handle(.escape)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.last == .hide)
    }

    @Test("タイムアウト後にパネルが消えたら、エラー表示で残ったパレットを閉じる")
    func panelGoneClosesPaletteLeftAfterTimeout() async {
        let harness = await Self.makeInjectingHarness()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)

        harness.coordinator.handle(.panelGone)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.last == .hide)
    }

    @Test("タイムアウト後にパネルを再検知すると PanelShown に戻り、パレットを表示し直す")
    func panelRedetectedAfterTimeout() async {
        let harness = await Self.makeInjectingHarness()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)

        harness.showPanel(.sample)

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.last == .show(.sample))
    }
}
