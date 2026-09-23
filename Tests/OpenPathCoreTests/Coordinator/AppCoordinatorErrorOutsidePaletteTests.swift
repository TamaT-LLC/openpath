import Testing

import OpenPathCore

/// 自動確定でパネルが閉じた後は、パレットでエラーを伝えられない。
/// そのうち利用者が気づくべきもの（クリップボードの復元失敗）は `onErrorOutsidePalette` で外へ伝える。
@Suite("AppCoordinator: パレットで伝えられないエラー", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorErrorOutsidePaletteTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    /// kAXErrorCannotComplete
    private nonisolated static let axCannotCompleteCode: Int32 = -25_204

    /// 伝えられたエラーを記録する。
    @MainActor
    final class ReportedErrors {
        private(set) var errors: [InjectionError] = []

        func append(_ error: InjectionError) {
            errors.append(error)
        }
    }

    /// 注入を始め、injector が呼ばれるまで進める。既定は Cmd+Enter（自動確定）。
    private static func makeInjectingHarness(reported: ReportedErrors, openImmediately: Bool = true) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.coordinator.onErrorOutsidePalette = { reported.append($0) }
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: path, openImmediately: openImmediately))
        await harness.injector.waitUntilCalled()
        return harness
    }

    /// 注入をクリップボードの復元失敗で終わらせ、パレットにエラーを出した（PanelShown）状態まで進める。
    private static func failWithPasteboardRestoreFailure(_ harness: CoordinatorHarness) async {
        harness.injector.resume(with: .failure(InjectionError.pasteboardRestoreFailed))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))
    }

    @Test("自動確定でパネルが閉じた後にクリップボードを戻せなかったら、パレットの外へ伝える")
    func reportsPasteboardRestoreFailureAfterPanelGone() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .failure(InjectionError.pasteboardRestoreFailed))
        await harness.waitForState(.idle)

        #expect(reported.errors == [.pasteboardRestoreFailed])
        #expect(harness.history.recordedPaths == [Self.path])
    }

    @Test(
        "パネルが閉じた後のそれ以外の結果は伝えない",
        arguments: [
            Result<Void, InjectionError>.success(()),
            .failure(.panelGone),
            .failure(.axError(code: axCannotCompleteCode)),
            .failure(.panelGoneBeforeConfirm),
        ]
    )
    func otherOutcomesAreNotReported(_ outcome: Result<Void, InjectionError>) async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: outcome.mapError { $0 as any Error })
        await harness.waitForState(.idle)

        #expect(reported.errors.isEmpty)
    }

    @Test("自動確定の復元失敗が panelGone より先に届いたら、続く panelGone で履歴に残してパレットの外へ伝える")
    func reportsPasteboardRestoreFailureBeforePanelGone() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)
        await Self.failWithPasteboardRestoreFailure(harness)
        let reportedBeforePanelGone = reported.errors

        harness.coordinator.handle(.panelGone)

        #expect(reportedBeforePanelGone.isEmpty)
        #expect(harness.coordinator.state == .idle)
        #expect(reported.errors == [.pasteboardRestoreFailed])
        #expect(harness.history.recordedPaths == [Self.path])
    }

    @Test("復元失敗を見て Esc した後にパネルが消えても、伝えず履歴にも残さない")
    func escapeClearsPendingPasteboardRestoreFailure() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)
        await Self.failWithPasteboardRestoreFailure(harness)

        harness.coordinator.handle(.escape)
        harness.coordinator.handle(.panelGone)

        #expect(reported.errors.isEmpty)
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("自動確定でない注入の復元失敗は、続く panelGone でも伝えず履歴にも残さない（「開く」は押していない）")
    func manualConfirmPasteboardRestoreFailureIsNotReportedOnPanelGone() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported, openImmediately: false)
        await Self.failWithPasteboardRestoreFailure(harness)

        harness.coordinator.handle(.panelGone)

        #expect(reported.errors.isEmpty)
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("復元失敗の後に再試行したら、前の失敗は panelGone で伝えない")
    func retryClearsPendingPasteboardRestoreFailure() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)
        await Self.failWithPasteboardRestoreFailure(harness)

        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled(times: 2)
        harness.injector.resume(callAt: 1, with: .failure(InjectionError.targetNotFrontmost))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))
        harness.coordinator.handle(.panelGone)

        #expect(reported.errors.isEmpty)
        #expect(harness.history.recordedPaths.isEmpty)
    }

    @Test("パレットを出している間のクリップボードの復元失敗はパレットに出し、外へは伝えない")
    func pasteboardRestoreFailureWithPaletteIsShownInPalette() async {
        let reported = ReportedErrors()
        let harness = await Self.makeInjectingHarness(reported: reported)

        harness.injector.resume(with: .failure(InjectionError.pasteboardRestoreFailed))
        await harness.waitForState(.panelShown(.sample, isPaletteVisible: true))

        #expect(reported.errors.isEmpty)
        let message = InjectionError.pasteboardRestoreFailed.userMessage
        #expect(message != nil)
        #expect(harness.palette.calls.last == message.map(PaletteSpy.Call.showError))
    }
}
