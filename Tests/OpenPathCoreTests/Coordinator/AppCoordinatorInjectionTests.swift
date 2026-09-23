import Testing

import OpenPathCore

@Suite("AppCoordinator: パス注入", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorInjectionTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204

    struct AutoConfirmCase: Sendable, CustomTestStringConvertible {
        let isAutoConfirmEnabled: Bool
        let openImmediately: Bool
        let expectsAutoConfirm: Bool

        var testDescription: String {
            "auto_confirm=\(isAutoConfirmEnabled), Cmd+Enter=\(openImmediately) → \(expectsAutoConfirm)"
        }
    }

    @Test("confirm で Injecting になり、パレットをロックして注入を開始する")
    func confirmStartsInjection() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))
        #expect(harness.palette.calls == [.show(.sample), .setLocked(true), .showStatus(PaletteMessage.injecting)])
        await harness.injector.waitUntilCalled()
        #expect(harness.injector.calls == [InjectorFake.Call(path: Self.path, autoConfirm: false)])
    }

    @Test("注入が成功すると Idle に戻り、履歴に記録してパレットを閉じる")
    func successfulInjectionRecordsHistory() async {
        let harness = CoordinatorHarness(injectorBehavior: .succeed)
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.path])
        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .hide])
        #expect(harness.observedStates == [
            .panelShown(.sample, isPaletteVisible: true),
            .injecting(.sample, path: Self.path),
            .idle,
        ])
    }

    @Test(
        "auto_confirm は設定値に従い、Cmd+Enter は設定に関わらず自動確定する",
        arguments: [
            AutoConfirmCase(isAutoConfirmEnabled: false, openImmediately: false, expectsAutoConfirm: false),
            AutoConfirmCase(isAutoConfirmEnabled: true, openImmediately: false, expectsAutoConfirm: true),
            AutoConfirmCase(isAutoConfirmEnabled: false, openImmediately: true, expectsAutoConfirm: true),
            AutoConfirmCase(isAutoConfirmEnabled: true, openImmediately: true, expectsAutoConfirm: true),
        ]
    )
    func autoConfirmFollowsSettingAndCommandEnter(_ testCase: AutoConfirmCase) async {
        let harness = CoordinatorHarness(injectorBehavior: .succeed)
        // 設定は confirm 時点の値が使われる（設定ファイルの変更を再起動なしで反映するため）
        harness.settings.isAutoConfirmEnabled = testCase.isAutoConfirmEnabled
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: testCase.openImmediately))
        await harness.waitForState(.idle)

        #expect(harness.injector.calls == [InjectorFake.Call(path: Self.path, autoConfirm: testCase.expectsAutoConfirm)])
    }

    @Test("注入が失敗するとパレットを残してエラーを表示し、PanelShown に戻る")
    func failedInjectionKeepsPaletteWithError() async throws {
        let error = InjectionError.timeout(step: .waitSheet)
        let expectedMessage = try #require(error.userMessage)
        let harness = CoordinatorHarness(injectorBehavior: .fail(error))
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .showError(expectedMessage)])
        #expect(!harness.palette.calls.contains(.hide))
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("InjectionError 以外のエラーでも汎用の文言でパレットに通知する")
    func unexpectedErrorShowsGenericMessage() async {
        struct UnexpectedError: Error {}
        let harness = CoordinatorHarness(injectorBehavior: .fail(UnexpectedError()))
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        #expect(harness.palette.calls.last == .showError(PaletteMessage.injectionFailed))
    }

    @Test("注入先のパネルが消えていた（panelGone エラー）場合はエラーを出さず Idle に戻る")
    func panelGoneErrorReturnsToIdle() async {
        let harness = CoordinatorHarness(injectorBehavior: .fail(InjectionError.panelGone))
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.idle)

        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .hide])
        #expect(!harness.palette.calls.contains { if case .showError = $0 { true } else { false } })
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("注入失敗後に再度 confirm すると再試行できる")
    func retryAfterFailure() async {
        let harness = CoordinatorHarness(injectorBehavior: .fail(InjectionError.axError(code: Self.axCannotCompleteCode)))
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: false))

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.anotherPath))
    }

    @Test("Injecting 中は入力をロックし、confirm / Esc / ホットキー / パネル検知を無視する")
    func inputsAreIgnoredWhileInjecting() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        let paletteCallsBeforeInputs = harness.palette.calls

        harness.coordinator.handle(.confirm(path: Self.anotherPath, openImmediately: true))
        harness.coordinator.handle(.escape)
        harness.coordinator.handle(.hotkey)
        harness.coordinator.handle(.panelAppeared(.another))
        await harness.injector.waitUntilCalled()
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))
        #expect(harness.palette.calls == paletteCallsBeforeInputs)
        #expect(harness.injector.calls == [InjectorFake.Call(path: Self.path, autoConfirm: false)])
    }

    @Test("空のパスの confirm は無視する")
    func emptyPathIsIgnored() async {
        let harness = CoordinatorHarness()
        harness.showPanel()

        harness.coordinator.handle(.confirm(path: "", openImmediately: false))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .panelShown(.sample, isPaletteVisible: true))
        #expect(harness.injector.calls.isEmpty)
    }
}
