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

    /// Cmd+Enter（自動確定）で注入を始め、injector が呼ばれるまで進める。
    private static func makeInjectingHarness(reported: ReportedErrors) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true))
        harness.coordinator.onErrorOutsidePalette = { reported.append($0) }
        harness.showPanel()
        harness.coordinator.handle(.confirm(path: path, openImmediately: true))
        await harness.injector.waitUntilCalled()
        return harness
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
