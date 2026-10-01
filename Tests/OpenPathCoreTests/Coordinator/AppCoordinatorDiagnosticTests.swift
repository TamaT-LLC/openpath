import Testing

import OpenPathCore

/// 注入の開始と、注入の失敗を覚える・出し直す・忘れることの診断（実機 QA の INJ-01・#101 を debug ログで判定するため）。
/// パネル id・失敗の種類・理由だけを報告し、確定したパスは報告しない。
@Suite("AppCoordinator: 診断の報告", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorDiagnosticTests {
    typealias Diagnostic = CoordinatorDiagnostic

    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204
    private static let notFrontmost = Diagnostic.FailureKind.injection(.targetNotFrontmost)
    private static let timedOut = Diagnostic.FailureKind.injection(.timeout(step: .overall))

    /// confirm して、注入が始まるまで進める。
    private static func makeInjectingHarness(
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
        return harness
    }

    /// 注入中に別のアプリへ切り替え（panelGone）、打ち切った注入の後始末まで進める（INJ-01）。
    private static func makeHarnessSwitchedAwayWhileInjecting() async -> CoordinatorHarness {
        let harness = await makeInjectingHarness()
        harness.coordinator.handle(.panelGone)
        await harness.injector.waitForCancellation()
        await harness.drainMainActor()
        return harness
    }

    // MARK: - 注入の開始

    @Test(
        "注入を始めたら、パネル id・自動確定か・再試行でないことを報告する",
        arguments: [(false, false, false), (true, false, true), (false, true, true)]
    )
    func reportsInjectionStart(isAutoConfirmEnabled: Bool, openImmediately: Bool, expectedAutoConfirm: Bool) async {
        let harness = await Self.makeInjectingHarness(isAutoConfirmEnabled: isAutoConfirmEnabled, openImmediately: openImmediately)

        #expect(harness.diagnostics.diagnostics == [
            .injectionStarted(panelID: PanelContext.sample.id, isAutoConfirm: expectedAutoConfirm, isRetry: false),
        ])
    }

    // MARK: - INJ-01（#94）

    @Test("注入中に切り替えたら失敗を覚え、戻ったパネルの再通知で出し直し、Enter で再試行したら忘れて再試行として注入を始める")
    func reportsRememberReshowAndRetry() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()

        harness.coordinator.handle(.panelAppeared(.sample))
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)

        #expect(harness.diagnostics.diagnostics == [
            .injectionStarted(panelID: PanelContext.sample.id, isAutoConfirm: false, isRetry: false),
            .failureRemembered(panelID: PanelContext.sample.id, failure: Self.notFrontmost, cause: .panelGoneWhileInjecting),
            .failureReshown(panelID: PanelContext.sample.id, failure: Self.notFrontmost),
            .failureForgotten(panelID: PanelContext.sample.id, failure: Self.notFrontmost, reason: .retry),
            .injectionStarted(panelID: PanelContext.sample.id, isAutoConfirm: false, isRetry: true),
        ])
    }

    @Test("出し直したパレットを Esc で閉じたら、Esc で忘れたことを報告する")
    func reportsForgottenByEscape() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        harness.coordinator.handle(.panelAppeared(.sample))

        harness.coordinator.handle(.escape)

        #expect(harness.diagnostics.diagnostics.last
            == .failureForgotten(panelID: PanelContext.sample.id, failure: Self.notFrontmost, reason: .escape))
    }

    @Test("覚えた失敗のあるまま別のパネルのパレットを出したら、別のパネルで忘れたことを報告する（出し直さない）")
    func reportsForgottenByOtherPanel() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()

        harness.coordinator.handle(.panelAppeared(.another))

        #expect(harness.diagnostics.diagnostics.suffix(2) == [
            .failureRemembered(panelID: PanelContext.sample.id, failure: Self.notFrontmost, cause: .panelGoneWhileInjecting),
            .failureForgotten(panelID: PanelContext.sample.id, failure: Self.notFrontmost, reason: .otherPanel),
        ])
    }

    @Test("失敗を表示しているパネルを見失ったら、表示中の失敗として覚えたことを報告する")
    func reportsRememberedWhileShowingFailure() async {
        let harness = await Self.makeInjectingHarness()
        harness.injector.resume(with: .failure(InjectionError.axError(code: Self.axCannotCompleteCode)))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        harness.coordinator.handle(.panelGone)

        #expect(harness.diagnostics.diagnostics.last == .failureRemembered(
            panelID: PanelContext.sample.id,
            failure: .injection(.axError(code: Self.axCannotCompleteCode)),
            cause: .panelGoneWhileShowingFailure
        ))
    }

    @Test("自動確定でパネルが消えた後に「開く」まで進まなかったら、パネル消滅後の失敗として覚えたことを報告する")
    func reportsRememberedAfterPanelGone() async {
        let harness = await Self.makeInjectingHarness(openImmediately: true)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .failure(InjectionError.targetNotFrontmost))
        await harness.waitForState(.idle)

        #expect(harness.diagnostics.diagnostics.last
            == .failureRemembered(panelID: PanelContext.sample.id, failure: Self.notFrontmost, cause: .finishedAfterPanelGone))
    }

    @Test("クリップボードを戻せなかった失敗を出したままパネルが閉じたら、パネルが閉じたため忘れたことを報告する")
    func reportsForgottenWhenPanelClosedAfterRestoreFailure() async {
        let harness = await Self.makeInjectingHarness(openImmediately: true)
        harness.injector.resume(with: .failure(InjectionError.pasteboardRestoreFailed))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        harness.coordinator.handle(.panelGone)

        #expect(harness.diagnostics.diagnostics.last == .failureForgotten(
            panelID: PanelContext.sample.id,
            failure: .injection(.pasteboardRestoreFailed),
            reason: .panelClosed
        ))
    }

    // MARK: - タイムアウト（#101）

    @Test("表示中にタイムアウトしたら失敗を覚え、再通知で出し直し、Idle で残ったパレットの Esc で忘れたことを報告する")
    func reportsTimeoutLifecycle() async {
        let harness = await Self.makeInjectingHarness()
        harness.clock.advance(by: AppCoordinator.injectionTimeout)
        await harness.waitForState(.idle)
        let remembered = harness.diagnostics.diagnostics.last

        harness.coordinator.handle(.panelAppeared(.sample))
        harness.coordinator.handle(.panelGone)
        harness.coordinator.handle(.escape)

        #expect(remembered == .failureRemembered(panelID: PanelContext.sample.id, failure: Self.timedOut, cause: .timedOut))
        #expect(harness.diagnostics.diagnostics.suffix(3) == [
            .failureReshown(panelID: PanelContext.sample.id, failure: Self.timedOut),
            .failureRemembered(panelID: PanelContext.sample.id, failure: Self.timedOut, cause: .panelGoneWhileShowingFailure),
            .failureForgotten(panelID: PanelContext.sample.id, failure: Self.timedOut, reason: .escape),
        ])
    }

    // MARK: - ログの文言

    @Test(
        "失敗の種類の表記",
        arguments: [
            (Diagnostic.FailureKind.injection(.targetNotFrontmost), "targetNotFrontmost"),
            (.injection(.timeout(step: .overall)), "timeout(overall)"),
            (.injection(.timeout(step: .waitSheet)), "timeout(waitSheet)"),
            (.injection(.axError(code: -25_204)), "axError(-25204)"),
            (.injection(.panelGone), "panelGone"),
            (.injection(.pasteboardRestoreFailed), "pasteboardRestoreFailed"),
            (.injection(.panelGoneBeforeConfirm), "panelGoneBeforeConfirm"),
            (.unknown, "unknown"),
        ]
    )
    func failureKindLabel(kind: Diagnostic.FailureKind, expected: String) {
        #expect(kind.logLabel == expected)
    }

    @Test("InjectionError 以外の失敗は unknown として扱う（エラーの説明文はパスを含み得るため使わない）")
    func nonInjectionErrorIsUnknown() {
        struct PathError: Error {}

        #expect(Diagnostic.FailureKind(PathError()) == .unknown)
        #expect(Diagnostic.FailureKind(InjectionError.targetNotFrontmost) == Self.notFrontmost)
    }

    @Test("それぞれの文言")
    func messages() {
        let id = PanelContext.sample.id

        #expect(Diagnostic.injectionStarted(panelID: id, isAutoConfirm: false, isRetry: true).logMessage
            == "coordinator injection start (id: panel-1, autoConfirm: false, retry: true)")
        #expect(Diagnostic.failureRemembered(panelID: id, failure: Self.notFrontmost, cause: .panelGoneWhileInjecting).logMessage
            == "coordinator failure remembered (id: panel-1, failure: targetNotFrontmost, cause: panelGoneWhileInjecting)")
        #expect(Diagnostic.failureReshown(panelID: id, failure: Self.timedOut).logMessage
            == "coordinator failure reshown (id: panel-1, failure: timeout(overall))")
        #expect(Diagnostic.failureForgotten(panelID: id, failure: Self.timedOut, reason: .escape).logMessage
            == "coordinator failure forgotten (id: panel-1, failure: timeout(overall), reason: escape)")
    }

    @Test("報告の文言は、確定したパスとログを読むスクリプトの目印を含まない")
    func messagesAreSafe() async {
        let harness = await Self.makeHarnessSwitchedAwayWhileInjecting()
        harness.coordinator.handle(.panelAppeared(.sample))
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)
        harness.coordinator.handle(.panelGone)
        harness.coordinator.handle(.panelAppeared(.another))

        let messages = harness.diagnostics.diagnostics.map(\.logMessage)
        #expect(messages.count >= 5)
        #expect(messages.allSatisfy(DiagnosticLogContract.isSafe))
        #expect(messages.allSatisfy { !$0.contains("fern") })
    }
}
