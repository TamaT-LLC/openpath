import Testing

import OpenPathCore

/// 自動確定中にパネルが消えると、AppCoordinator は注入を止めずに結果を待つ（#52）。
/// その結果が成功か panelGone なら「開く」でパネルが閉じたとみなして履歴に残すため、
/// injector は「開く」を押す前に止めた注入をそれ以外のエラーで返す。この取り決めを AppCoordinator と組み合わせて確かめる。
@Suite("PathInjectionFlow と AppCoordinator の自動確定の取り決め", .timeLimit(.minutes(1)))
@MainActor
struct AutoConfirmCoordinatorContractTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"

    @Test(
        "自動確定中にパネルが消えた後、「開く」を押す前に止めた注入の結果は履歴に残らない",
        arguments: [InjectionError.panelGoneBeforeConfirm, .targetNotFrontmost]
    )
    func injectionStoppedBeforeOpenIsNotRecorded(error: InjectionError) async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: true), isAutoConfirmEnabled: true)
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: Self.path, openImmediately: false))
        await harness.injector.waitUntilCalled()
        harness.coordinator.handle(.panelGone)

        harness.injector.resume(with: .failure(error))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths.isEmpty)
    }
}
