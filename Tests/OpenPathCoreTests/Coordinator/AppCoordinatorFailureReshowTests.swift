import Testing

import OpenPathCore

/// 注入中に別のアプリへ切り替えると、PanelWatcher は panelGone を送り、元のアプリに戻ると開いたままのパネルを
/// 再通知する（PR #46）。切り替えている間はパレットを他のアプリの上に出さず、戻ったときの再通知で
/// 注入の失敗をパレットに赤字で出し直す（#94、INJ-01）。
@Suite("AppCoordinator: アプリの切り替えで見せられなかった注入の失敗", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorFailureReshowTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204

    /// 自動確定になる操作。
    enum AutoConfirmTrigger: CaseIterable, Sendable, CustomTestStringConvertible {
        /// 設定 auto_confirm=true で Enter
        case setting
        /// 設定 auto_confirm=false で Cmd+Enter
        case commandEnter

        var isAutoConfirmEnabled: Bool {
            self == .setting
        }

        var openImmediately: Bool {
            self == .commandEnter
        }

        var testDescription: String {
            switch self {
            case .setting:
                "auto_confirm=true で Enter"
            case .commandEnter:
                "Cmd+Enter"
            }
        }
    }

    /// 自動確定中にパネルが消えた後の注入の結果のうち、パネルが閉じた（「開く」を押した、または押す前に閉じられた）とみなすもの。
    enum ClosedPanelOutcome: CaseIterable, Sendable, CustomTestStringConvertible {
        case succeeded
        case panelGone
        case pasteboardRestoreFailed
        case panelGoneBeforeConfirm

        var result: Result<Void, any Error> {
            switch self {
            case .succeeded:
                .success(())
            case .panelGone:
                .failure(InjectionError.panelGone)
            case .pasteboardRestoreFailed:
                .failure(InjectionError.pasteboardRestoreFailed)
            case .panelGoneBeforeConfirm:
                .failure(InjectionError.panelGoneBeforeConfirm)
            }
        }

        var testDescription: String {
            "\(self)"
        }
    }

    private static var notFrontmostMessage: String {
        get throws { try #require(InjectionError.targetNotFrontmost.userMessage) }
    }

    /// 自動確定でない Enter で confirm して、注入が始まるまで進める。
    private static func makeInjectingHarness() async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: path, openImmediately: false))
        await harness.injector.waitUntilCalled()
        return harness
    }

    /// 自動確定で confirm して、注入が始まるまで進める。
    private static func makeAutoConfirmInjectingHarness(_ trigger: AutoConfirmTrigger) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(
            injectorBehavior: .suspend(respondsToCancellation: true),
            isAutoConfirmEnabled: trigger.isAutoConfirmEnabled
        )
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: path, openImmediately: trigger.openImmediately))
        await harness.injector.waitUntilCalled()
        return harness
    }

    /// 注入中に別のアプリへ切り替えた（panelGone を受けた）状態まで進める。打ち切った注入の後始末も待つ。
    private static func makeHarnessSwitchedAwayWhileInjecting() async -> CoordinatorHarness {
        let harness = await makeInjectingHarness()
        harness.coordinator.handle(.panelGone)
        await harness.injector.waitForCancellation()
        await harness.drainMainActor()
        return harness
    }

    private static func containsError(_ calls: some Sequence<PaletteSpy.Call>) -> Bool {
        calls.contains { if case .showError = $0 { true } else { false } }
    }

    // MARK: - 注入中に切り替えた（panelGone が注入の結果より先）

    @Test("注入中に別のアプリへ切り替えている間は、パレットを閉じたままにする")
    func paletteStaysHiddenWhileSwitchedAway() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        let paletteCallsAfterSwitch = harness.palette.calls

        // 切り替え先でホットキーを押しても、別のアプリの上にパレットを出さない
        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(paletteCallsAfterSwitch.suffix(2) == [.setLocked(false), .hide])
        #expect(!Self.containsError(paletteCallsAfterSwitch))
        #expect(harness.palette.calls == paletteCallsAfterSwitch)
    }

    @Test("元のアプリに戻ってパネルが再通知されたら、パレットに「パネルが最前面でなくなりました」を出す")
    func reappearanceShowsNotFrontmostError() async throws {
        let message = try Self.notFrontmostMessage
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        let paletteCallsBeforeReturn = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeReturn.count)) == [
            .show(.sample),
            .showError(message),
        ])
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("エラーを出し直したパレットから Enter で再試行できる")
    func retryFromReshownPalette() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))
        #expect(harness.injector.calls.last == InjectorFake.Call(path: Self.path, autoConfirm: false))
    }

    @Test("エラーを出し直したパレットは Esc で閉じられ、その後のホットキーではエラーを出さない")
    func escapeClosesReshownPalette() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.escape)
        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: false))
        #expect(harness.palette.calls.last == .hide)
        let paletteCallsAfterEscape = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsAfterEscape.count)) == [.show(.sample)])
    }

    @Test("注入を始める前に切り替えた場合も、戻ったときにエラーを出す")
    func switchBeforeInjectionStartsIsReshown() async throws {
        let message = try Self.notFrontmostMessage
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        harness.coordinator.handle(.panelGone)
        await harness.drainMainActor()

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.injector.calls.isEmpty)
        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
    }

    // MARK: - 失敗を表示した後に切り替わった（注入の結果が panelGone より先）

    @Test(
        "失敗を表示した直後にパネルを見失っても、戻ったときの再通知でそのエラーを出し直す",
        arguments: [InjectionError.targetNotFrontmost, .timeout(step: .waitSheet)]
    )
    func errorShownBeforePanelGoneIsReshown(error: InjectionError) async throws {
        let message = try #require(error.userMessage)
        let harness = CoordinatorHarness(injectorBehavior: .fail(error))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        harness.coordinator.handle(.panelGone)
        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls.last == .hide)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
    }

    @Test("出し直したエラーは、もう一度切り替えて戻っても出し直す")
    func reshownErrorSurvivesAnotherSwitch() async throws {
        let message = try Self.notFrontmostMessage
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.panelGone)
        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
    }

    @Test("Esc で閉じてから見失ったパネルの再通知では、エラーを出さない")
    func errorDismissedByEscapeIsNotReshown() async {
        let harness = CoordinatorHarness(injectorBehavior: .fail(InjectionError.targetNotFrontmost))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))
        harness.coordinator.handle(.escape)
        harness.coordinator.handle(.panelGone)
        let paletteCallsBeforeReturn = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeReturn.count)) == [.show(.sample)])
    }

    // MARK: - 覚えたエラーを忘れる

    @Test("切り替えている間に別のパネルのパレットを出したら、覚えたエラーを忘れる")
    func anotherPanelForgetsFailure() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()

        harness.coordinator.handle(.panelAppeared(.another))
        #expect(harness.palette.calls.last == .show(.another))
        // 別のパネルへの注入に成功して Idle に戻る（panelGone を経ずに Idle で再通知を受ける経路）
        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)
        harness.injector.resume(callAt: 1, with: .success(()))
        await harness.waitForState(.idle)
        let paletteCallsBeforeReturn = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeReturn.count)) == [.show(.sample)])
    }

    @Test("覚えたエラーは別のパネルの再通知では出さない")
    func failureIsNotShownForAnotherPanel() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        let paletteCallsBeforeAnother = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.another))

        #expect(harness.coordinator.state == .panelShown(.another, isPaletteVisible: true))
        #expect(Array(harness.palette.calls.dropFirst(paletteCallsBeforeAnother.count)) == [.show(.another)])
    }

    @Test("再試行に成功した後は、成功したパネルの再通知を従来どおり抑止する")
    func successAfterRetryKeepsSuppression() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
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

    // MARK: - 自動確定

    @Test(
        "自動確定中に切り替えて注入が targetNotFrontmost で終わったら、戻ったときの再通知でエラーを出す",
        arguments: AutoConfirmTrigger.allCases
    )
    func autoConfirmNotFrontmostIsReshown(_ trigger: AutoConfirmTrigger) async throws {
        let message = try Self.notFrontmostMessage
        let harness = await Self.makeAutoConfirmInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)
        harness.injector.resume(with: .failure(InjectionError.targetNotFrontmost))
        await harness.waitForState(.idle)
        #expect(!Self.containsError(harness.palette.calls))

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test(
        "自動確定中にパネルが消えた後の失敗・タイムアウトも、同じパネルが再通知されたらエラーを出す",
        arguments: AutoConfirmTrigger.allCases, [false, true]
    )
    func autoConfirmOtherFailureIsReshown(_ trigger: AutoConfirmTrigger, timesOut: Bool) async throws {
        let error = timesOut ? InjectionError.timeout(step: .overall) : .axError(code: Self.axCannotCompleteCode)
        let message = try #require(error.userMessage)
        let harness = await Self.makeAutoConfirmInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)
        if timesOut {
            harness.clock.advance(by: AppCoordinator.injectionTimeout)
        } else {
            harness.injector.resume(with: .failure(error))
        }
        await harness.waitForState(.idle)

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(harness.palette.calls.suffix(2) == [.show(.sample), .showError(message)])
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test(
        "自動確定中にパネルが閉じたとみなす結果では、エラーを覚えない",
        arguments: AutoConfirmTrigger.allCases, ClosedPanelOutcome.allCases
    )
    func autoConfirmClosedPanelIsNotReshown(_ trigger: AutoConfirmTrigger, outcome: ClosedPanelOutcome) async {
        let harness = await Self.makeAutoConfirmInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)
        harness.injector.resume(with: outcome.result)
        await harness.waitForState(.idle)
        let paletteCallsBeforeReappearance = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))

        #expect(!Self.containsError(harness.palette.calls.dropFirst(paletteCallsBeforeReappearance.count)))
    }
}
