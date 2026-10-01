import Testing

import OpenPathCore

/// パレットの表示中に注入が 1.5 秒でタイムアウトすると、パネルの状態が分からないため Idle に戻り（PR #39）、
/// エラーを出したパレットは残す。PanelWatcher は Idle に戻ると開いたままのパネルを再通知する（PR #46）。
/// 再通知でパレットを出し直してもタイムアウトのエラーを付け直し、検索語と選択を残したまま
/// Enter で再試行・Esc で閉じられるようにする（#101）。
@Suite("AppCoordinator: 表示中の注入タイムアウトのエラーの付け直し", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorTimeoutReshowTests {
    typealias AutoConfirmTrigger = AppCoordinatorFailureReshowTests.AutoConfirmTrigger

    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"

    private static var timedOutMessage: String {
        get throws { try #require(InjectionError.timeout(step: .overall).userMessage) }
    }

    /// パレットから confirm して注入を始め、パネルが開いたまま 1.5 秒でタイムアウトさせて Idle に戻すまで進める。
    /// PanelWatcher の再通知（同じ id の panelAppeared）はまだ届いていない。
    private static func makeTimedOutHarness(
        isAutoConfirmEnabled: Bool = false,
        openImmediately: Bool = false
    ) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(
            injectorBehavior: .suspend(respondsToCancellation: true),
            isAutoConfirmEnabled: isAutoConfirmEnabled
        )
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: path, openImmediately: openImmediately))
        await harness.injector.waitUntilCalled()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)
        return harness
    }

    // MARK: - 再通知でエラーを付け直す

    @Test("タイムアウト後の同じパネルの再通知では、パレットを出し直してタイムアウトのエラーを付け直す")
    func reannouncementReattachesTimeoutError() async throws {
        let message = try Self.timedOutMessage
        let harness = await Self.makeTimedOutHarness()
        let paletteCallsAtTimeout = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        // タイムアウトの時点ではパレットを閉じずにエラーを出す（従来どおり）
        #expect(paletteCallsAtTimeout.suffix(2) == [.setLocked(false), .showError(message)])
        #expect(!paletteCallsAtTimeout.contains(.hide))
        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(Array(harness.palette.calls.dropFirst(paletteCallsAtTimeout.count)) == [
            .show(.sample),
            .showError(message),
        ])
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("エラーを付け直したパレットから Enter で再試行できる")
    func retryFromReattachedPalette() async {
        let harness = await Self.makeTimedOutHarness()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))
        #expect(harness.injector.calls.last == InjectorFake.Call(path: Self.path, autoConfirm: false))
    }

    @Test("エラーを付け直したパレットは Esc で閉じられ、その後のホットキーではエラーを出さない")
    func escapeClosesReattachedPalette() async {
        let harness = await Self.makeTimedOutHarness()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.escape)
        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.palette.calls.last == .hide)
        let paletteCallsAfterEscape = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsAfterEscape.count)) == [.show(.sample)])
    }

    @Test(
        "自動確定でもパネルが開いたままタイムアウトしたら、再通知でエラーを付け直し、履歴には残さない",
        arguments: AutoConfirmTrigger.allCases
    )
    func autoConfirmTimeoutReattachesError(_ trigger: AutoConfirmTrigger) async throws {
        let message = try Self.timedOutMessage
        let harness = await Self.makeTimedOutHarness(
            isAutoConfirmEnabled: trigger.isAutoConfirmEnabled,
            openImmediately: trigger.openImmediately
        )

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
        #expect(harness.history.recordedPaths.isEmpty)
    }

    // MARK: - 見失ったパネル

    @Test("タイムアウトのエラーを出したまま見失ったパネルが戻ってきたら、エラーを出す")
    func panelLostAfterTimeoutReshowsError() async throws {
        let message = try Self.timedOutMessage
        let harness = await Self.makeTimedOutHarness()

        harness.coordinator.handle(.panelGone)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.last == .hide)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
    }

    @Test("付け直したエラーは、もう一度見失って戻っても出し直す")
    func reattachedErrorSurvivesPanelLoss() async throws {
        let message = try Self.timedOutMessage
        let harness = await Self.makeTimedOutHarness()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.panelGone)
        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
    }

    // MARK: - 覚えたエラーを忘れる

    @Test("再通知の前に Esc でエラー表示のパレットを閉じたら、再通知ではエラーを出さない")
    func escapeBeforeReannouncementForgetsError() async {
        let harness = await Self.makeTimedOutHarness()

        harness.coordinator.handle(.escape)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.last == .hide)
        let paletteCallsAfterEscape = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsAfterEscape.count)) == [.show(.sample)])
    }

    @Test("別のパネルのパレットを出したら、タイムアウトのエラーを忘れる")
    func anotherPanelForgetsTimeoutError() async {
        let harness = await Self.makeTimedOutHarness()
        let paletteCallsBeforeAnother = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.another))
        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeAnother.count)) == [.show(.another)])
        harness.coordinator.handle(.panelGone)
        let paletteCallsBeforeReturn = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeReturn.count)) == [.show(.sample)])
    }

    // MARK: - 既存の振る舞いを保つ

    @Test("タイムアウトの後も、ホットキーは従来どおり無視する（切り替え先のアプリの上にパレットを出さない）")
    func hotkeyAfterTimeoutIsIgnored() async {
        let harness = await Self.makeTimedOutHarness()
        harness.coordinator.handle(.panelGone)
        let paletteCallsAfterPanelGone = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterPanelGone)
    }

    @Test("再試行に成功した後は、成功したパネルの再通知を従来どおり抑止する")
    func successAfterRetryKeepsSuppression() async {
        let harness = await Self.makeTimedOutHarness()
        harness.coordinator.handle(.panelAppeared(.sample))
        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)
        harness.injector.resume(callAt: 1, with: .success(()))
        await harness.waitForState(.idle)
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterSuccess)
        #expect(harness.history.recordedPaths == [Self.anotherPath])
    }
}
