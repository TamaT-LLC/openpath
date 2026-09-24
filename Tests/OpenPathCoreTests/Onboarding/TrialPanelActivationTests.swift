import Testing

import OpenPathCore

@Suite("TrialPanelActivation: 「試してみる」のダイアログを前面に出す待ち合わせと再試行の判定（Issue #72）")
struct TrialPanelActivationTests {
    private static let timing = TrialPanelActivationTiming(
        pollInterval: .milliseconds(50),
        retryInterval: .milliseconds(200),
        maxAttempts: 3,
        timeout: .seconds(5)
    )

    @Test("既定の待ち方: 50ms ごとに確かめ、200ms ごとに最大 5 回送り、10 秒で諦める")
    func standardTiming() {
        let timing = TrialPanelActivationTiming.standard

        // UIElement に変わってからダイアログが出るまで（実測 50〜70ms）の間に前面に出せるよう、細かく確かめる
        #expect(timing.pollInterval == .milliseconds(50))
        #expect(timing.retryInterval == .milliseconds(200))
        #expect(timing.maxAttempts == 5)
        #expect(timing.timeout == .seconds(10))
    }

    @Test("登録前・prohibited の間は要求を送らず、試行にも数えない", arguments: [TrialPanelProcessState.notRegistered, .backgroundOnly])
    func waitsWhileProcessCannotBeActivated(state: TrialPanelProcessState) {
        var activation = TrialPanelActivation(timing: Self.timing)

        #expect(activation.next(observing: state, at: .zero) == .wait)
        #expect(activation.next(observing: state, at: .milliseconds(100)) == .wait)
        #expect(activation.attempts == 0)
    }

    @Test("前面に出せる状態になったら要求を送る")
    func activatesWhenReady() {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .backgroundOnly, at: .milliseconds(100))

        #expect(activation.next(observing: .inactive, at: .milliseconds(1_000)) == .activate)
        #expect(activation.attempts == 1)
    }

    @Test("要求の後は retryInterval が過ぎるまで送り直さず、過ぎてもまだ前面に出ていなければ送り直す")
    func retriesAfterRetryInterval() {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .inactive, at: .milliseconds(1_000))

        #expect(activation.next(observing: .inactive, at: .milliseconds(1_050)) == .wait)
        #expect(activation.next(observing: .inactive, at: .milliseconds(1_150)) == .wait)
        #expect(activation.next(observing: .inactive, at: .milliseconds(1_200)) == .activate)
        #expect(activation.attempts == 2)
    }

    @Test("前面に出たと確かめたら、試行の回数と経過時間を添えて終える")
    func finishesWhenActive() {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .inactive, at: .milliseconds(1_000))

        let action = activation.next(observing: .active, at: .milliseconds(1_050))

        #expect(action == .finish(TrialPanelActivationOutcome(status: .activated, attempts: 1, elapsed: .milliseconds(1_050))))
    }

    @Test("閉じられたら、要求の反映を待たずに終える")
    func finishesWhenExited() {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .inactive, at: .milliseconds(1_000))

        let action = activation.next(observing: .exited, at: .milliseconds(1_050))

        #expect(action == .finish(TrialPanelActivationOutcome(status: .exited, attempts: 1, elapsed: .milliseconds(1_050))))
    }

    @Test("試行の上限に達したら、最後の要求の反映を retryInterval だけ待ってから諦める")
    func givesUpAfterMaxAttempts() {
        var activation = TrialPanelActivation(timing: Self.timing)
        #expect(activation.next(observing: .inactive, at: .milliseconds(1_000)) == .activate)
        #expect(activation.next(observing: .inactive, at: .milliseconds(1_200)) == .activate)
        #expect(activation.next(observing: .inactive, at: .milliseconds(1_400)) == .activate)

        #expect(activation.next(observing: .inactive, at: .milliseconds(1_550)) == .wait)
        let action = activation.next(observing: .inactive, at: .milliseconds(1_600))

        #expect(action == .finish(TrialPanelActivationOutcome(
            status: .notActivated(lastState: .inactive),
            attempts: 3,
            elapsed: .milliseconds(1_600)
        )))
    }

    @Test("最後の要求で前面に出たら、上限に達していても成功として終える")
    func succeedsOnLastAttempt() {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .inactive, at: .milliseconds(1_000))
        _ = activation.next(observing: .inactive, at: .milliseconds(1_200))
        _ = activation.next(observing: .inactive, at: .milliseconds(1_400))

        let action = activation.next(observing: .active, at: .milliseconds(1_450))

        #expect(action == .finish(TrialPanelActivationOutcome(status: .activated, attempts: 3, elapsed: .milliseconds(1_450))))
    }

    @Test("待ち時間の上限を過ぎたら、最後に確かめた状態を添えて諦める", arguments: [
        TrialPanelProcessState.notRegistered, .backgroundOnly, .inactive,
    ])
    func givesUpAtTimeout(state: TrialPanelProcessState) {
        var activation = TrialPanelActivation(timing: Self.timing)
        _ = activation.next(observing: .notRegistered, at: .zero)

        let action = activation.next(observing: state, at: .seconds(5))

        #expect(action == .finish(TrialPanelActivationOutcome(
            status: .notActivated(lastState: state),
            attempts: 0,
            elapsed: .seconds(5)
        )))
    }

    @Test("上限の直前に送った要求は、上限を過ぎても反映を待つ")
    func waitsForPendingAttemptPastTimeout() {
        var activation = TrialPanelActivation(timing: Self.timing)
        #expect(activation.next(observing: .inactive, at: .milliseconds(4_950)) == .activate)

        #expect(activation.next(observing: .inactive, at: .seconds(5)) == .wait)
        #expect(activation.next(observing: .active, at: .milliseconds(5_050)) == .finish(TrialPanelActivationOutcome(
            status: .activated,
            attempts: 1,
            elapsed: .milliseconds(5_050)
        )))
    }
}

@Suite("TrialPanelActivationOutcome: 前面に出す処理の結果のログ")
struct TrialPanelActivationOutcomeTests {
    @Test("前面に出たら、試行の回数と経過時間（ミリ秒）を残す")
    func activatedMessage() {
        let outcome = TrialPanelActivationOutcome(status: .activated, attempts: 2, elapsed: .milliseconds(1_234))

        #expect(outcome.logMessage == "「試してみる」のダイアログを前面に出しました（試行 2 回、1234ms）")
        #expect(!outcome.needsUserAction)
    }

    @Test("閉じられたら、前面に出る前に閉じられたことを残す")
    func exitedMessage() {
        let outcome = TrialPanelActivationOutcome(status: .exited, attempts: 0, elapsed: .milliseconds(500))

        #expect(outcome.logMessage == "「試してみる」のダイアログは前面に出る前に閉じられました（試行 0 回、500ms）")
        #expect(!outcome.needsUserAction)
    }

    @Test("前面に出せなかったら、最後の状態と、ダイアログをクリックすればよいことを残す")
    func notActivatedMessage() {
        let outcome = TrialPanelActivationOutcome(
            status: .notActivated(lastState: .backgroundOnly),
            attempts: 0,
            elapsed: .seconds(10)
        )

        #expect(outcome.logMessage == "「試してみる」のダイアログを前面に出せませんでした（試行 0 回、10000ms、最後の状態: backgroundOnly）。"
            + "ダイアログをクリックするとパレットが出ます")
        #expect(outcome.needsUserAction)
    }

    @Test("ミリ秒は切り捨てる")
    func truncatesMilliseconds() {
        let outcome = TrialPanelActivationOutcome(status: .activated, attempts: 1, elapsed: .microseconds(1_999))

        #expect(outcome.logMessage.contains("、1ms）"))
    }
}
