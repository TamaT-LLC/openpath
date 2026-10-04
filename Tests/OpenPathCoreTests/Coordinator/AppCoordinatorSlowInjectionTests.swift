import Testing

import OpenPathCore

/// Issue #29 の実機 QA（macOS 26 の VS Code）で、初回の注入は移動先シートが ③（システム経由の ⌘⇧G）で +887ms に開いたが、
/// その後のペーストと確定が間に合わず、1.5 秒の全体タイムアウトで `timeout(overall)` になった。
/// 失敗する注入は各段の待ち（200 / 300 / 500ms など）で先に打ち切られるため、全体タイムアウトを 2.5 秒に延ばし、
/// 遅いが成功する注入だけを待つ（オーナー決定）。
@Suite("AppCoordinator: 遅いが成功する注入を全体タイムアウトで打ち切らない（Issue #29）", .timeLimit(.minutes(1)))
@MainActor
struct AppCoordinatorSlowInjectionTests {
    private typealias Diagnostic = CoordinatorDiagnostic

    private static let path = SlowSheetInjection.path
    /// 全体タイムアウト（Issue #29 のオーナー決定）。
    private static let overallTimeout: Duration = .milliseconds(2_500)
    private static let justBeforeTimeout = Duration.milliseconds(1)
    private static let timedOut = Diagnostic.FailureKind.injection(.timeout(step: .overall))

    /// Cmd+Enter で confirm して、注入が始まるまで進める。
    private static func makeInjectingHarness(respondsToCancellation: Bool = true) async -> CoordinatorHarness {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: respondsToCancellation))
        harness.showPanel(.sample)
        harness.coordinator.handle(.confirm(path: path, openImmediately: true))
        await harness.injector.waitUntilCalled()
        return harness
    }

    private static func containsError(_ calls: [PaletteSpy.Call]) -> Bool {
        calls.contains { if case .showError = $0 { true } else { false } }
    }

    @Test(
        "初回の ③ で移動先シートが約 900ms に出て 1.5 秒を超える注入も、全体タイムアウトの前に終われば成功として履歴に残す",
        arguments: SlowSheetInjection.allCases
    )
    func slowInjectionWithinOverallTimeoutIsRecorded(_ injection: SlowSheetInjection) async throws {
        // PathInjectionFlow がこの注入にかかる時間を測り、AppCoordinator の時計を同じだけ進めてから注入を終える
        let flow = injection.makeHarness()
        try await flow.run(path: Self.path, autoConfirm: true)
        let harness = await Self.makeInjectingHarness()

        harness.clock.advance(by: flow.clock.elapsed)
        await harness.drainMainActor()
        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))

        harness.injector.resume(with: .success(()))
        await harness.waitForState(.idle)

        #expect(harness.history.recordedPaths == [Self.path])
        #expect(!Self.containsError(harness.palette.calls))
        #expect(!harness.injector.isCancelled)
    }

    @Test("全体タイムアウトは 2.5 秒。2.5 秒に達するまでは待ち、達しても終わらなければ timeout(overall) で打ち切り、遅れて届いた成功は履歴に残さない")
    func injectionStillRunningAtTwoAndAHalfSecondsTimesOut() async throws {
        let expectedMessage = try #require(InjectionError.timeout(step: .overall).userMessage)
        let harness = await Self.makeInjectingHarness(respondsToCancellation: false)

        harness.clock.advance(by: Self.overallTimeout - Self.justBeforeTimeout)
        await harness.drainMainActor()
        #expect(harness.coordinator.state == .injecting(.sample, path: Self.path))

        harness.clock.advance(by: Self.justBeforeTimeout)
        await harness.waitForState(.idle)
        #expect(harness.palette.calls.suffix(2) == [.setLocked(false), .showError(expectedMessage)])
        #expect(harness.diagnostics.diagnostics.last == .failureRemembered(
            panelID: PanelContext.sample.id,
            failure: Self.timedOut,
            cause: .timedOut
        ))
        await harness.injector.waitForCancellation()

        harness.injector.resume(with: .success(()))
        await harness.drainMainActor()

        #expect(harness.coordinator.state == .idle)
        #expect(harness.history.recordedPaths.isEmpty)
    }
}
