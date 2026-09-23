import Testing

import OpenPathCore

@Suite("OpenButtonAutoConfirm: auto_confirm / Cmd+Enter で「開く」を押す（DSN-001 §3.1 ステップ 8、FR-INJECT-03）", .timeLimit(.minutes(1)))
@MainActor
struct OpenButtonAutoConfirmTests {
    /// kAXErrorFailure
    private static let axFailureCode: Int32 = -25_200
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let openButton: PanelElementFake
        let locator: OpenButtonLocatorFake
        let targetGuard: TargetGuardFake
        let autoConfirm: OpenButtonAutoConfirm

        init() {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            openButton = PanelElementFake("open", log: log)
            locator = OpenButtonLocatorFake(clock: clock, log: log)
            locator.button = openButton
            targetGuard = TargetGuardFake(log: log)
            targetGuard.logsChecks = true
            autoConfirm = OpenButtonAutoConfirm(locator: locator, targetGuard: targetGuard, timing: .standard, clock: clock)
        }

        func confirm(autoConfirm isEnabled: Bool = true) async throws {
            try await autoConfirm.confirm(autoConfirm: isEnabled)
        }
    }

    @Test("待ち時間の既定値は DSN-001 §3.1 ステップ 8 のとおり 300ms")
    func standardTiming() {
        #expect(PanelControlTiming.standard.openButtonDelay == .milliseconds(300))
        #expect(PanelControlTiming.standard.controlLookupLimit == .milliseconds(300))
    }

    @Test("auto_confirm でなければ、待たず、探さず、押さない（既定は自動で開かない: FR-INJECT-03）")
    func doesNothingWithoutAutoConfirm() async throws {
        let harness = Harness()

        try await harness.confirm(autoConfirm: false)

        #expect(harness.log.entries.isEmpty)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("300ms 待ってから「開く」を探し、注入先を確かめてから押す")
    func pressesOpenButtonAfterDelay() async throws {
        let harness = Harness()

        try await harness.confirm()

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .milliseconds(300), event: .lookUpOpenButton),
            .init(time: .milliseconds(300), event: .targetCheck),
            .init(time: .milliseconds(300), event: .press(element: "open")),
        ]
        #expect(harness.log.entries == expected)
    }

    @Test("PathInjectionHooks に渡す hook も同じように振る舞う")
    func hookBehavesLikeConfirm() async throws {
        let enabled = Harness()
        let disabled = Harness()

        try await enabled.autoConfirm.hook(true)
        try await disabled.autoConfirm.hook(false)

        #expect(enabled.log.events.last == .press(element: "open"))
        #expect(disabled.log.events.isEmpty)
    }

    @Test("「開く」が見つからなければ axError(failure) を投げる")
    func throwsWhenOpenButtonIsMissing() async {
        let harness = Harness()
        harness.locator.button = nil

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.confirm()
        }
    }

    @Test("探すのが 300ms を超えたら打ち切り、axError(cannotComplete) を投げて押さない")
    func lookupCutOffByDeadline() async {
        let harness = Harness()
        harness.locator.lookupLatency = .milliseconds(400)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.confirm()
        }

        #expect(harness.log.events.contains(.scanCutOff))
        #expect(!harness.log.events.contains(.press(element: "open")))
        #expect(harness.clock.elapsed == .milliseconds(600))
    }

    @Test(
        "押す前に注入先が無くなっていたら、押さずにそのエラーを投げる",
        arguments: [InjectionError.panelGone, .axError(code: axCannotCompleteCode)]
    )
    func propagatesLookupFailure(error: InjectionError) async {
        let harness = Harness()
        harness.locator.error = error

        await #expect(throws: error) {
            try await harness.confirm()
        }

        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    @Test(
        "押す直前の確認で注入先が無効なら、押さずに投げる",
        arguments: [
            (status: InjectionTargetStatus.notFrontmost, error: InjectionError.targetNotFrontmost),
            (status: InjectionTargetStatus.gone, error: InjectionError.panelGone),
        ]
    )
    func doesNotPressWhenTargetIsLost(lost: (status: InjectionTargetStatus, error: InjectionError)) async {
        let harness = Harness()
        harness.targetGuard.invalidation = (fromCheck: 0, status: lost.status)

        await #expect(throws: lost.error) {
            try await harness.confirm()
        }

        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    @Test("押した後にパネルが消えるのは正常なので、成功として返す")
    func succeedsWhenPanelClosesAfterPress() async throws {
        let harness = Harness()
        harness.openButton.disappearsWhenActivated = true

        try await harness.confirm()

        #expect(harness.openButton.isGone)
    }

    @Test(
        "押下が失敗を返しても、ボタンが消えていれば（パネルが閉じた）成功として返す",
        arguments: [InjectionError.axError(code: axCannotCompleteCode), .panelGone]
    )
    func succeedsWhenPressFailsButPanelClosed(error: InjectionError) async throws {
        let harness = Harness()
        harness.openButton.pressError = error
        harness.openButton.disappearsWhenActivated = true

        try await harness.confirm()
    }

    @Test("押下が失敗し、ボタンが残っていれば axError を投げる")
    func throwsWhenPressFailsAndPanelRemains() async {
        let harness = Harness()
        harness.openButton.pressError = InjectionError.axError(code: Self.axCannotCompleteCode)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.confirm()
        }
    }

    @Test("押下が InjectionError 以外で失敗し、ボタンが残っていれば axError(failure) を投げる")
    func unknownPressFailureIsAXFailure() async {
        let harness = Harness()
        harness.openButton.pressError = AdapterFailure()

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.confirm()
        }
    }

    @Test("300ms の待機中にキャンセルされたら、探さずに CancellationError を投げる")
    func cancelledWhileWaiting() async {
        let harness = Harness()
        let task = Task { [autoConfirm = harness.autoConfirm] in
            cancelCurrentTask()
            try await autoConfirm.confirm(autoConfirm: true)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(harness.log.entries.isEmpty)
    }

    @Test("探している最中にキャンセルされたら、走査が打ち切り条件でそれを検知し、押さずに CancellationError を投げる")
    func cancelledWhileLookingUp() async {
        let harness = Harness()
        let suspension = Suspension()
        harness.locator.suspension = suspension
        let task = Task { [autoConfirm = harness.autoConfirm] in
            try await autoConfirm.confirm(autoConfirm: true)
        }

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(harness.log.events.contains(.scanCutOff))
        #expect(!harness.log.events.contains(.press(element: "open")))
    }
}
