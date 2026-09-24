import Testing

import OpenPathCore

@Suite("TrialPanelActivator: 「試してみる」のダイアログを前面に出すまで待って送り直す（Issue #72）", .timeLimit(.minutes(1)))
@MainActor
struct TrialPanelActivatorTests {
    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let process: TrialProcessFake
        let activator: TrialPanelActivator

        init(timing: TrialPanelActivationTiming = .standard) {
            let process = TrialProcessFake(clock: clock)
            self.process = process
            activator = TrialPanelActivator(
                timing: timing,
                clock: clock,
                observe: { process.state() },
                activate: { process.activate() }
            )
        }

        func run() async -> TrialPanelActivationOutcome? {
            await activator.run()
        }
    }

    @Test("登録直後（prohibited）には要求を送らず、UIElement に変わってから送って前面に出す")
    func waitsUntilProcessCanBeActivated() async {
        let harness = Harness()

        let outcome = await harness.run()

        // 変更前は登録を見つけた 100ms に 1 度だけ要求し、断られて諦めていた
        #expect(harness.process.activationRequests == [.milliseconds(1_000)])
        #expect(outcome == TrialPanelActivationOutcome(status: .activated, attempts: 1, elapsed: .milliseconds(1_050)))
    }

    @Test("要求が断られたら、間隔を空けて送り直し、前面に出たら終える")
    func retriesUntilActivated() async {
        let harness = Harness()
        harness.process.refusalsRemaining = 2

        let outcome = await harness.run()

        #expect(harness.process.activationRequests == [.milliseconds(1_000), .milliseconds(1_200), .milliseconds(1_400)])
        #expect(outcome == TrialPanelActivationOutcome(status: .activated, attempts: 3, elapsed: .milliseconds(1_450)))
    }

    @Test("試行の上限まで前面に出なければ、最後の要求の反映を待ってから諦める")
    func givesUpAfterMaxAttempts() async {
        let harness = Harness()
        harness.process.refusalsRemaining = .max

        let outcome = await harness.run()

        #expect(harness.process.activationRequests.count == TrialPanelActivationTiming.standard.maxAttempts)
        #expect(harness.process.activationRequests.last == .milliseconds(1_800))
        #expect(outcome == TrialPanelActivationOutcome(
            status: .notActivated(lastState: .inactive),
            attempts: 5,
            elapsed: .milliseconds(2_000)
        ))
        #expect(outcome?.needsUserAction == true)
    }

    @Test("UIElement に変わらないまま待ち時間の上限を過ぎたら、要求を送らずに諦める")
    func givesUpWhenProcessNeverBecomesReady() async {
        let harness = Harness()
        harness.process.readyAt = .seconds(60)

        let outcome = await harness.run()

        #expect(harness.process.activationRequests.isEmpty)
        #expect(outcome == TrialPanelActivationOutcome(
            status: .notActivated(lastState: .backgroundOnly),
            attempts: 0,
            elapsed: .seconds(10)
        ))
    }

    @Test("アプリとして登録されないまま上限を過ぎたら、登録前だったことを返す")
    func givesUpWhenProcessNeverRegisters() async {
        let harness = Harness()
        harness.process.registeredAt = .seconds(60)

        let outcome = await harness.run()

        #expect(outcome?.status == .notActivated(lastState: .notRegistered))
    }

    @Test("前面に出る前にダイアログが閉じられたら、要求を送らずに終える")
    func stopsWhenProcessExits() async {
        let harness = Harness()
        harness.process.exitedAt = .milliseconds(500)

        let outcome = await harness.run()

        #expect(harness.process.activationRequests.isEmpty)
        #expect(outcome == TrialPanelActivationOutcome(status: .exited, attempts: 0, elapsed: .milliseconds(500)))
    }

    @Test("既に前面に出ていれば（開いているダイアログを出し直すとき）、要求を送らずに終える")
    func finishesImmediatelyWhenAlreadyActive() async {
        let harness = Harness()
        harness.process.isActive = true

        let outcome = await harness.run()

        #expect(harness.process.activationRequests.isEmpty)
        #expect(outcome == TrialPanelActivationOutcome(status: .activated, attempts: 0, elapsed: .zero))
    }

    @Test("開いているダイアログを出し直すときは、UIElement なのですぐに要求を送る")
    func activatesImmediatelyWhenAlreadyReady() async {
        let harness = Harness()
        harness.process.registeredAt = .zero
        harness.process.readyAt = .zero

        let outcome = await harness.run()

        #expect(harness.process.activationRequests == [.zero])
        #expect(outcome == TrialPanelActivationOutcome(status: .activated, attempts: 1, elapsed: .milliseconds(50)))
    }

    @Test("状態は pollInterval ごとに確かめる")
    func checksAtPollInterval() async {
        let timing = TrialPanelActivationTiming(
            pollInterval: .milliseconds(100),
            retryInterval: .milliseconds(300),
            maxAttempts: 2,
            timeout: .seconds(2)
        )
        let harness = Harness(timing: timing)
        harness.process.readyAt = .milliseconds(950)

        let outcome = await harness.run()

        // 950ms に UIElement になり、次に確かめる 1000ms で要求し、その次の 1100ms で前面に出たと確かめる
        #expect(harness.process.activationRequests == [.milliseconds(1_000)])
        #expect(outcome == TrialPanelActivationOutcome(status: .activated, attempts: 1, elapsed: .milliseconds(1_100)))
    }

    @Test("キャンセルされたら結果を返さず、要求も送らない")
    func cancellation() async {
        let harness = Harness()

        let task = Task { await harness.run() }
        task.cancel()
        let outcome = await task.value

        #expect(outcome == nil)
        #expect(harness.process.activationRequests.isEmpty)
    }
}
