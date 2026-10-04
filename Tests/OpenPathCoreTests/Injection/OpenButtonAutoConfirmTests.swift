import Testing

import OpenPathCore

@Suite("OpenButtonAutoConfirm: auto_confirm / Cmd+Enter で「開く」を押す（DSN-001 §3.1 ステップ 8、FR-INJECT-03）", .timeLimit(.minutes(1)))
@MainActor
struct OpenButtonAutoConfirmTests {
    /// kAXErrorFailure
    nonisolated private static let axFailureCode: Int32 = -25_200
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

    @Test(
        "300ms は確定（Return）から数える。シートが閉じるのを確かめる間に過ぎた分は待たない（Issue #95）",
        arguments: [
            (Duration.milliseconds(100), Duration.milliseconds(200)),
            (.milliseconds(300), .zero),
            (.milliseconds(400), .zero),
        ]
    )
    func countsDelayFromSubmit(elapsedSinceSubmit: Duration, expectedWait: Duration) async throws {
        let harness = Harness()

        try await harness.autoConfirm.confirm(autoConfirm: true, elapsedSinceSubmit: elapsedSinceSubmit)

        #expect(harness.log.entries.first == .init(time: expectedWait, event: .lookUpOpenButton))
        #expect(harness.log.events.last == .press(element: "open"))
    }

    @Test("hook に渡された、確定からの経過時間も同じように差し引く")
    func hookCountsDelayFromSubmit() async throws {
        let harness = Harness()

        try await harness.autoConfirm.hook(true, .milliseconds(250))

        #expect(harness.log.entries.first == .init(time: .milliseconds(50), event: .lookUpOpenButton))
    }

    @Test("PathInjectionHooks に渡す hook も同じように振る舞う")
    func hookBehavesLikeConfirm() async throws {
        let enabled = Harness()
        let disabled = Harness()

        try await enabled.autoConfirm.hook(true, .zero)
        try await disabled.autoConfirm.hook(false, .zero)

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

    // MARK: - 押せる状態になるまで待つ・探し直す（Issue #89）

    @Test("「開く」を探して押せる状態になるまで待つ上限は、探し始めから累積 300ms、確かめ直す間隔は 50ms")
    func standardReadyTiming() {
        #expect(PanelControlTiming.standard.openButtonReadyLimit == .milliseconds(300))
        #expect(PanelControlTiming.standard.openButtonPollInterval == .milliseconds(50))
    }

    @Test("「開く」が押せない状態（AXEnabled が false）なら、押せる状態になるまで 50ms 間隔で待ってから押す（探し直さない）")
    func waitsUntilOpenButtonIsEnabled() async throws {
        let harness = Harness()
        harness.openButton.enabledProvider = { [clock = harness.clock] in clock.elapsed >= .milliseconds(420) }

        try await harness.confirm()

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .milliseconds(300), event: .lookUpOpenButton),
            .init(time: .milliseconds(450), event: .targetCheck),
            .init(time: .milliseconds(450), event: .press(element: "open")),
        ]
        #expect(harness.log.entries == expected)
        // 300 / 350 / 400 / 450ms
        #expect(harness.openButton.enabledReadCount == 4)
        #expect(harness.locator.lookupCount == 1)
    }

    @Test("押せる状態にならないまま期限（探し始めから 300ms）を迎えたら、押さずに axError(cannotComplete) を投げる")
    func throwsWhenOpenButtonStaysDisabled() async {
        let harness = Harness()
        harness.openButton.enabledValue = false

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.confirm()
        }

        #expect(!harness.log.events.contains(.press(element: "open")))
        // 最後の確認は期限（600ms）より前の 550ms
        #expect(harness.openButton.enabledReadCount == 6)
        #expect(harness.clock.elapsed == .milliseconds(550))
    }

    @Test("押せる状態か分からない（属性が無い）ときは、待たずに押す（従来どおり）")
    func pressesWhenEnabledStateIsUnknown() async throws {
        let harness = Harness()
        harness.openButton.enabledValue = nil

        try await harness.confirm()

        #expect(harness.log.entries.last == .init(time: .milliseconds(300), event: .press(element: "open")))
    }

    @Test(
        "押せる状態を読めない（要素が消えた以外の AX の失敗）ときは、待たずに押す（従来どおり）",
        arguments: [InjectionError.axError(code: axCannotCompleteCode), .axError(code: axFailureCode)]
    )
    func pressesWhenEnabledStateCannotBeRead(error: InjectionError) async throws {
        let harness = Harness()
        harness.openButton.enabledReadError = error

        try await harness.confirm()

        #expect(harness.log.entries.last == .init(time: .milliseconds(300), event: .press(element: "open")))
    }

    @Test("「開く」がすぐに見つからなくても、期限までは 50ms 間隔で探し直し、現れたら押す（移動直後の作り直し）")
    func findsOpenButtonThatAppearsLater() async throws {
        let harness = Harness()
        harness.locator.buttonProvider = { [clock = harness.clock, openButton = harness.openButton] in
            clock.elapsed >= .milliseconds(400) ? openButton : nil
        }

        try await harness.confirm()

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .milliseconds(300), event: .lookUpOpenButton),
            .init(time: .milliseconds(350), event: .lookUpOpenButton),
            .init(time: .milliseconds(400), event: .lookUpOpenButton),
            .init(time: .milliseconds(400), event: .targetCheck),
            .init(time: .milliseconds(400), event: .press(element: "open")),
        ]
        #expect(harness.log.entries == expected)
    }

    @Test("期限まで探し直しても見つからなければ axError(failure) を投げる")
    func throwsWhenOpenButtonNeverAppears() async {
        let harness = Harness()
        harness.locator.button = nil

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.confirm()
        }

        // 300 / 350 / … / 550ms
        #expect(harness.locator.lookupCount == 6)
        #expect(harness.clock.elapsed == .milliseconds(550))
    }

    @Test("探し直しても見つからず、最後の探索が期限で打ち切られた場合も、見つからない（axError(failure)）として投げる")
    func reportsMissingWhenLastLookupIsCutOff() async {
        let harness = Harness()
        harness.locator.button = nil
        harness.locator.lookupLatency = .milliseconds(150)

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.confirm()
        }

        // 300→450ms（見つからない）、500ms からの 2 回目は 600ms の期限を過ぎた最初の AX 操作の前で打ち切る
        #expect(harness.locator.lookupCount == 2)
        #expect(harness.log.events.contains(.scanCutOff))
        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    @Test("待っている間にボタンが消えた（作り直された）ら、探し直して新しいボタンを押す")
    func relocatesRebuiltOpenButton() async throws {
        let harness = Harness()
        let staleButton = PanelElementFake("stale", log: harness.log)
        staleButton.enabledReadError = InjectionError.panelGone
        harness.locator.buttonProvider = { [locator = harness.locator, openButton = harness.openButton] in
            locator.lookupCount == 1 ? staleButton : openButton
        }

        try await harness.confirm()

        #expect(harness.locator.lookupCount == 2)
        #expect(harness.log.entries.last == .init(time: .milliseconds(350), event: .press(element: "open")))
        #expect(!harness.log.events.contains(.press(element: "stale")))
    }

    @Test("探す時間も、押せる状態を待つ時間も、累積の期限（探し始めから 300ms）に含める")
    func lookupTimeCountsTowardReadyLimit() async {
        let harness = Harness()
        harness.locator.lookupLatency = .milliseconds(200)
        harness.openButton.enabledValue = false

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.confirm()
        }

        // 探し終えた 500ms と 550ms に確かめ、600ms の期限より前に打ち切る
        #expect(harness.openButton.enabledReadCount == 2)
        #expect(harness.clock.elapsed == .milliseconds(550))
        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    @Test("押せる状態を待っている間にキャンセルされたら、押さずに CancellationError を投げる")
    func cancelledWhileWaitingForEnabled() async {
        let harness = Harness()
        harness.openButton.enabledProvider = {
            cancelCurrentTask()
            return false
        }
        let task = Task { [autoConfirm = harness.autoConfirm] in
            try await autoConfirm.confirm(autoConfirm: true)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!harness.log.events.contains(.press(element: "open")))
    }
}
