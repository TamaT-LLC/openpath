import Testing

import OpenPathCore

/// 自動確定（auto_confirm / Cmd+Enter）では、injector が最後に「開く」を押すためパネルが閉じ、
/// 注入の完了より先に PanelWatcher から panelGone が届く。その場合も注入の結果を待って履歴に残す。
@Suite("AppCoordinator: 自動確定中のパネル消滅", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorAutoConfirmTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let justBeforeTimeout = Duration.milliseconds(1)
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

    private static func makeHarness(_ trigger: AutoConfirmTrigger, injectorBehavior: InjectorFake.Behavior) -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: injectorBehavior, isAutoConfirmEnabled: trigger.isAutoConfirmEnabled)
        harness.showPanel(.sample)
        return harness
    }

    /// 自動確定で confirm して、注入が始まるまで進める。
    private static func makeInjectingHarness(_ trigger: AutoConfirmTrigger) async -> CoordinatorHarness {
        let harness = makeHarness(trigger, injectorBehavior: .suspend(respondsToCancellation: true))
        harness.coordinator.handle(.confirm(path: path, openImmediately: trigger.openImmediately))
        await harness.injector.waitUntilCalled()
        return harness
    }

    private static func containsError(_ calls: [PaletteSpy.Call]) -> Bool {
        calls.contains { if case .showError = $0 { true } else { false } }
    }

    @Test("注入中にパネルが消えても注入をキャンセルせず、パレットだけ閉じて結果を待つ", arguments: AutoConfirmTrigger.allCases)
    func panelGoneDoesNotCancelInjection(_ trigger: AutoConfirmTrigger) async {
        let harness = await Self.makeInjectingHarness(trigger)

        harness.coordinator.handle(.panelGone)
        await harness.drainMainActor()

        #expect(harness.injector.calls == [InjectorFake.Call(path: Self.path, autoConfirm: true)])
        #expect(!harness.injector.isCancelled)
        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))
        #expect(harness.palette.calls.last == .hide)
    }

    @Test("パネルが消えた後に注入が成功したら、履歴に記録して Idle に戻る", arguments: AutoConfirmTrigger.allCases)
    func successAfterPanelGoneRecordsHistory(_ trigger: AutoConfirmTrigger) async {
        let harness = await Self.makeInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .success(()))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.path])
        #expect(harness.palette.calls.suffix(2) == [.hide, .setLocked(false)])
        #expect(!Self.containsError(harness.palette.calls))
    }

    /// injector の panelGone と、元の結果より優先して伝えられるペーストボードの復元失敗は、
    /// 「開く」まで進んだかが分からないため、パネルの消滅を根拠に成功とみなす。
    @Test(
        "パネルが消えた後に injector が panelGone / ペーストボード復元失敗で終えたら、「開く」でパネルが閉じたとみなして記録する",
        arguments: AutoConfirmTrigger.allCases, [InjectionError.panelGone, .pasteboardRestoreFailed]
    )
    func ambiguousErrorAfterPanelGoneCountsAsSuccess(_ trigger: AutoConfirmTrigger, error: InjectionError) async {
        let harness = await Self.makeInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .failure(error))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.path])
        #expect(!Self.containsError(harness.palette.calls))
    }

    @Test("パネルが消えた後に注入が失敗したら、エラーを出さずに Idle に戻り、履歴に残さない", arguments: AutoConfirmTrigger.allCases)
    func failureAfterPanelGoneIsNotRecorded(_ trigger: AutoConfirmTrigger) async {
        let harness = await Self.makeInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .failure(InjectionError.axError(code: Self.axCannotCompleteCode)))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths.isEmpty)
        // パネルは消えているため、パレットは閉じたまま出し直さない
        #expect(harness.palette.calls.suffix(2) == [.hide, .setLocked(false)])
        #expect(!Self.containsError(harness.palette.calls))
    }

    @Test("パネルが消えた後も 1.5 秒のタイムアウトは維持し、エラーを出さずに注入を止める", arguments: AutoConfirmTrigger.allCases)
    func timeoutIsKeptAfterPanelGone(_ trigger: AutoConfirmTrigger) async {
        let harness = await Self.makeInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)

        harness.clock.advance(by: AppCoordinator.injectionTimeout - Self.justBeforeTimeout)
        await harness.drainMainActor()
        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))

        harness.clock.advance(by: Self.justBeforeTimeout)
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths.isEmpty)
        #expect(harness.palette.calls.suffix(2) == [.hide, .setLocked(false)])
        #expect(!Self.containsError(harness.palette.calls))
        await harness.injector.waitForCancellation()
        #expect(harness.injector.isCancelled)
    }

    @Test("注入を始める前にパネルが消えたら、自動確定でも注入を始めない", arguments: AutoConfirmTrigger.allCases)
    func panelGoneBeforeInjectionStartsCancelsInjection(_ trigger: AutoConfirmTrigger) async {
        let harness = Self.makeHarness(trigger, injectorBehavior: .suspend(respondsToCancellation: true))
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: trigger.openImmediately))

        harness.coordinator.handle(.panelGone)
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.injector.calls.isEmpty)
        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .hide])
    }

    @Test("パネルが消えた後に注入が成功しても、そのパネルをホットキーの再表示先として残さない", arguments: AutoConfirmTrigger.allCases)
    func hotkeyIsIgnoredAfterSuccessWithPanelGone(_ trigger: AutoConfirmTrigger) async {
        let harness = await Self.makeInjectingHarness(trigger)
        harness.coordinator.handle(.panelGone)
        harness.injector.resume(with: .success(()))
        await harness.waitForState(.idle)
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.coordinator.handle(.hotkey)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.palette.calls == paletteCallsAfterSuccess)
    }

    @Test("パネルが消える前に注入が成功した場合、閉じかけのパネルの再通知ではパレットを出さない", arguments: AutoConfirmTrigger.allCases)
    func reappearanceBeforePanelGoneIsIgnored(_ trigger: AutoConfirmTrigger) async {
        let harness = Self.makeHarness(trigger, injectorBehavior: .succeed)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: trigger.openImmediately))
        await harness.waitForState(.idle)
        let paletteCallsAfterSuccess = harness.palette.calls

        harness.coordinator.handle(.panelAppeared(.sample))
        harness.coordinator.handle(.panelGone)

        #expect(harness.coordinator.state == .idle)
        #expect(harness.history.recordedPaths == [Self.path])
        #expect(!harness.palette.calls.dropFirst(paletteCallsAfterSuccess.count).contains(.show(.sample)))
    }
}
