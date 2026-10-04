import Testing

import OpenPathCore

@Suite("GoToSheetCloseWait: 確定した移動先シートが閉じるのを待つ（Issue #95）", .timeLimit(.minutes(1)))
@MainActor
struct GoToSheetCloseWaitTests {
    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let field: PanelElementFake
        let locator: GoToFieldLocatorFake
        let wait: GoToSheetCloseWait

        init() {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            field = PanelElementFake("path", log: log)
            locator = GoToFieldLocatorFake(clock: clock, log: log)
            locator.logsLookups = false
            locator.field = field
            wait = GoToSheetCloseWait(locator: locator, clock: clock)
        }

        /// 確定した入力欄（macOS 13 以降の移動先シートの入力欄。AXIdentifier で特定した）。
        var controls: GoToFieldControls {
            GoToFieldControls(field: field, goButton: nil, evidence: .pathFieldIdentifier)
        }

        func waitUntilClosed() async throws -> GoToSheetClosure {
            try await wait.waitUntilClosed(controls: controls)
        }

        /// at 以降、注入先のウィンドウから移動先シートの入力欄が見つからなくなる（シートが外れた）。
        func detachSheet(at time: Duration) {
            let clock = clock
            let field = field
            locator.fieldProvider = { clock.elapsed >= time ? nil : field }
        }
    }

    @Test("待ち時間の既定値: Return から 600ms まで、50ms 間隔で確かめる。1 回の走査は 150ms まで")
    func standardTiming() {
        let timing = GoToSheetCloseTiming.standard

        #expect(timing.waitLimit == .milliseconds(600))
        #expect(timing.pollInterval == .milliseconds(50))
        #expect(timing.lookupLimit == .milliseconds(150))
    }

    @Test("入力欄の要素が消えたら（AX の要素が無効になった）、その回は探し直さずに closed を返す")
    func closedWhenFieldDisappears() async throws {
        let harness = Harness()
        harness.field.isGoneProvider = { [clock = harness.clock] in clock.elapsed >= .milliseconds(200) }

        #expect(try await harness.waitUntilClosed() == .closed)
        #expect(harness.clock.elapsed == .milliseconds(200))
        // 0・50・100・150ms は開いたままのため探し、200ms は要素が消えたので探さない
        #expect(harness.locator.lookupCount == 4)
    }

    @Test("入力欄の要素が残っていても、注入先のウィンドウから移動先シートの入力欄が見つからなくなれば closed（閉じたシートが破棄されずに残る場合）")
    func closedWhenSheetIsDetachedFromWindow() async throws {
        let harness = Harness()
        harness.detachSheet(at: .milliseconds(150))

        #expect(try await harness.waitUntilClosed() == .closed)
        #expect(harness.clock.elapsed == .milliseconds(150))
    }

    @Test("600ms まで閉じなければ stillOpen を返す。Return の直後から 50ms 間隔で確かめる")
    func stillOpenWhenSheetRemains() async throws {
        let harness = Harness()

        #expect(try await harness.waitUntilClosed() == .stillOpen)
        #expect(harness.clock.elapsed == .milliseconds(600))
        // 0, 50, …, 600ms の 13 回
        #expect(harness.locator.lookupCount == 13)
    }

    @Test("見つかるのが手掛かりの弱い入力欄（placeholder）だけなら、確定した入力欄（AXIdentifier）のシートは閉じた（パネルの別の入力欄と取り違えない）")
    func closedWhenOnlyWeakerEvidenceRemains() async throws {
        let harness = Harness()
        harness.locator.evidence = .placeholder

        #expect(try await harness.waitUntilClosed() == .closed)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("確定した入力欄を見つけていなければ、最初に見つけた入力欄を基準に確かめる。見つけた後に見つからなくなれば closed")
    func usesFirstLocatedFieldWithoutControls() async throws {
        let harness = Harness()
        harness.detachSheet(at: .milliseconds(200))

        #expect(try await harness.wait.waitUntilClosed(controls: nil) == .closed)
        #expect(harness.clock.elapsed == .milliseconds(200))
    }

    @Test("確定した入力欄を見つけておらず、待っても一度も見つからなければ、閉じたとは言えないため unavailable を返す")
    func unavailableWhenFieldIsNeverFound() async throws {
        let harness = Harness()
        harness.locator.field = nil

        #expect(try await harness.wait.waitUntilClosed(controls: nil) == .unavailable)
        #expect(harness.clock.elapsed == .milliseconds(600))
        #expect(harness.locator.lookupCount == 13)
    }

    @Test("探せない（AX の失敗）ままなら、閉じたとも開いたままとも分からないため unavailable を返す")
    func unavailableWhenNeverReadable() async throws {
        let harness = Harness()
        harness.locator.error = InjectionError.axError(code: -25_204)

        #expect(try await harness.waitUntilClosed() == .unavailable)
        #expect(harness.clock.elapsed == .milliseconds(600))
    }

    @Test("一度でも開いたままなのを確かめていれば、その後に探せなくなっても stillOpen を返す")
    func stillOpenWhenOpenStateWasSeen() async throws {
        let harness = Harness()
        // 2 回目の確認から探せなくなる
        harness.locator.errorProvider = { [locator = harness.locator] in
            locator.lookupCount >= 2 ? InjectionError.axError(code: -25_204) : nil
        }

        #expect(try await harness.waitUntilClosed() == .stillOpen)
    }

    @Test("走査が上限（150ms）を超えたら、その回は分からないものとして確かめ続ける")
    func keepsCheckingWhenLookupIsCutOff() async throws {
        let harness = Harness()
        harness.locator.lookupLatency = .milliseconds(200)
        harness.field.isGoneProvider = { [clock = harness.clock] in clock.elapsed >= .milliseconds(400) }

        #expect(try await harness.waitUntilClosed() == .closed)
        #expect(harness.log.events.contains(.scanCutOff))
    }

    @Test("待っている間にキャンセルされたら CancellationError を投げる")
    func cancelledWhileWaiting() async {
        let harness = Harness()
        let suspension = Suspension()
        harness.locator.suspension = suspension
        let task = Task { [harness] in
            try await harness.waitUntilClosed()
        }

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
