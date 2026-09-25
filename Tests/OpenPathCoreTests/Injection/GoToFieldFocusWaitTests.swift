import Testing

import OpenPathCore

@Suite("GoToFieldFocusWait: キー入力の前に移動先シートの入力欄がフォーカスを持つまで待つ（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFieldFocusWaitTests {
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let field: PanelElementFake
        let locator: GoToFieldLocatorFake
        let wait: GoToFieldFocusWait

        init() {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            field = PanelElementFake("path", log: log)
            locator = GoToFieldLocatorFake(clock: clock, log: log)
            locator.field = field
            wait = GoToFieldFocusWait(locator: locator, clock: clock)
        }

        /// この経過時間以降の読み取りで、入力欄がフォーカスを持つことにする。nil なら持たない。
        func focusArrives(at time: Duration?) {
            field.focusProvider = { [clock] in
                time.map { clock.elapsed >= $0 } ?? false
            }
        }

        func waitUntilFocused(controls: GoToFieldControls? = nil) async throws -> GoToFieldFocusResult {
            try await wait.waitUntilFocused(controls: controls)
        }
    }

    @Test("待ち時間の既定値: 探すのは 150ms まで、フォーカスは探し始めてから 250ms まで 50ms 間隔で待つ")
    func standardTiming() {
        let timing = GoToFieldFocusTiming.standard

        #expect(timing.lookupLimit == .milliseconds(150))
        #expect(timing.waitLimit == .milliseconds(250))
        #expect(timing.pollInterval == .milliseconds(50))
    }

    @Test("入力欄が既にフォーカスを持っていれば、待たずに focused と見つけた入力欄を返す")
    func focusedImmediately() async throws {
        let harness = Harness()

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .focused)
        #expect(result.controls?.field as? PanelElementFake === harness.field)
        #expect(harness.clock.elapsed == .zero)
        #expect(harness.field.focusReadCount == 1)
        #expect(harness.locator.lookupCount == 1)
    }

    @Test("フォーカスが遅れて来たら 50ms ごとに確かめ直し、来た時点で focused を返す")
    func waitsUntilFocusArrives() async throws {
        let harness = Harness()
        // macOS 26 では、移動先シートが AX に現れてから入力欄がキー入力の受け先になるまで間がある（Issue #74）
        harness.focusArrives(at: .milliseconds(120))

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .focused)
        #expect(harness.clock.elapsed == .milliseconds(150))
        #expect(harness.field.focusReadCount == 4)
    }

    @Test("250ms までにフォーカスが来なければ notFocused を返す。AX でフォーカスを与えることはしない")
    func givesUpWhenFocusNeverArrives() async throws {
        let harness = Harness()
        harness.focusArrives(at: nil)

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .notFocused)
        #expect(result.controls != nil)
        #expect(harness.clock.elapsed == .milliseconds(250))
        #expect(harness.field.focusReadCount == 6)
        #expect(!harness.log.events.contains(.focusField(element: "path")))
    }

    @Test("期限（250ms）ちょうどに来たフォーカスは、最後の確認で拾う")
    func focusArrivingAtDeadlineIsAccepted() async throws {
        let harness = Harness()
        harness.focusArrives(at: .milliseconds(250))

        #expect(try await harness.waitUntilFocused().focus == .focused)
        #expect(harness.clock.elapsed == .milliseconds(250))
    }

    @Test("入力欄を探す時間も上限に含める（探すのに 100ms かかれば、確かめるのは 100〜250ms の間）")
    func lookupTimeCountsTowardLimit() async throws {
        let harness = Harness()
        harness.locator.lookupLatency = .milliseconds(100)
        harness.focusArrives(at: nil)

        #expect(try await harness.waitUntilFocused().focus == .notFocused)
        #expect(harness.clock.elapsed == .milliseconds(250))
        #expect(harness.field.focusReadCount == 4)
    }

    @Test("待っている間に入力欄が消えたら（移動先シートが閉じた）、fieldGone を返す")
    func fieldDisappearsWhileWaiting() async throws {
        let harness = Harness()
        harness.field.focusProvider = { [clock = harness.clock, field = harness.field] in
            if clock.elapsed >= .milliseconds(100) {
                field.focusReadError = InjectionError.panelGone
            }
            return false
        }

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .fieldGone)
        #expect(harness.clock.elapsed == .milliseconds(150))
    }

    @Test(
        "フォーカスを読めなければ（AX の失敗・InjectionError 以外）、待たずに unavailable と見つけた入力欄を返す",
        arguments: [
            InjectionError.axError(code: axCannotCompleteCode) as any Error,
            AdapterFailure(),
        ]
    )
    func focusReadFailureIsUnavailable(error: any Error) async throws {
        let harness = Harness()
        harness.field.focusReadError = error

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .unavailable)
        #expect(result.controls != nil)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("入力欄が見つからなければ、待たずに unavailable を返す")
    func unavailableWithoutField() async throws {
        let harness = Harness()
        harness.locator.field = nil

        let result = try await harness.waitUntilFocused()

        #expect(result.focus == .unavailable)
        #expect(result.controls == nil)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test(
        "探すのに失敗したら（AX の失敗・パネルが消えた・InjectionError 以外）、投げずに unavailable を返す",
        arguments: [
            InjectionError.axError(code: axCannotCompleteCode) as any Error,
            InjectionError.panelGone,
            AdapterFailure(),
        ]
    )
    func lookupFailureIsUnavailable(error: any Error) async throws {
        let harness = Harness()
        harness.locator.error = error

        #expect(try await harness.waitUntilFocused().focus == .unavailable)
    }

    @Test("探すのが 150ms を超えたら打ち切り、unavailable を返す")
    func lookupCutOffIsUnavailable() async throws {
        let harness = Harness()
        // 走査は 4 回の AX 操作に分かれ、150ms を過ぎた後の操作の前で打ち切られる
        harness.locator.lookupLatency = .milliseconds(600)

        #expect(try await harness.waitUntilFocused().focus == .unavailable)
        #expect(harness.log.events.contains(.scanCutOff))
        #expect(harness.clock.elapsed == .milliseconds(150))
    }

    @Test("見つけ済みの入力欄を渡されたら、探し直さない（副方式・確定前の確認と同じ入力欄を使う）")
    func usesKnownControls() async throws {
        let harness = Harness()
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        let result = try await harness.waitUntilFocused(controls: controls)

        #expect(result.focus == .focused)
        #expect(harness.locator.lookupCount == 0)
    }

    @Test(
        "いまのフォーカスを 1 回だけ読む（Return の直前の確認）: 待たず、探し直さない",
        arguments: [
            (hasFocus: true, error: nil, expected: GoToFieldFocus.focused),
            (hasFocus: false, error: nil, expected: .notFocused),
            (hasFocus: false, error: InjectionError.panelGone, expected: .fieldGone),
            (hasFocus: false, error: InjectionError.axError(code: axCannotCompleteCode), expected: .unavailable),
        ] as [(hasFocus: Bool, error: InjectionError?, expected: GoToFieldFocus)]
    )
    func readsCurrentFocusOnce(state: (hasFocus: Bool, error: InjectionError?, expected: GoToFieldFocus)) async throws {
        let harness = Harness()
        harness.field.hasFocus = state.hasFocus
        harness.field.focusReadError = state.error
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        #expect(try await harness.wait.currentFocus(of: controls) == state.expected)
        #expect(harness.field.focusReadCount == 1)
        #expect(harness.locator.lookupCount == 0)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("AX でフォーカスを与えて入力欄が持てば、待たずに focused を返す")
    func requestFocusSucceeds() async throws {
        let harness = Harness()
        harness.field.hasFocus = false
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        #expect(try await harness.wait.requestFocus(of: controls) == .focused)
        #expect(harness.log.events == [.focusField(element: "path")])
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("与えた直後にまだ持っていなければ、間隔 1 回分（50ms）待って確かめ直す")
    func requestFocusWaitsOneInterval() async throws {
        let harness = Harness()
        harness.field.acceptsFocusRequest = false
        harness.focusArrives(at: .milliseconds(30))
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        #expect(try await harness.wait.requestFocus(of: controls) == .focused)
        #expect(harness.clock.elapsed == .milliseconds(50))
        #expect(harness.field.focusReadCount == 2)
    }

    @Test("与えても持たなければ（与えるのに失敗した場合も）、50ms 後に notFocused を返す")
    func requestFocusFails() async throws {
        let harness = Harness()
        harness.field.hasFocus = false
        harness.field.focusRequestError = InjectionError.axError(code: Self.axCannotCompleteCode)
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        #expect(try await harness.wait.requestFocus(of: controls) == .notFocused)
        #expect(harness.clock.elapsed == .milliseconds(50))
    }

    @Test("与えるのに失敗しても、入力欄がフォーカスを持っていれば focused を返す")
    func requestFocusErrorButFocused() async throws {
        let harness = Harness()
        harness.field.focusRequestError = InjectionError.axError(code: Self.axCannotCompleteCode)
        let controls = GoToFieldControls(field: harness.field, goButton: nil)

        #expect(try await harness.wait.requestFocus(of: controls) == .focused)
    }

    @Test("与えた後にフォーカスを読めなければ unavailable、入力欄が消えていれば fieldGone を返す")
    func requestFocusUnreadable() async throws {
        let harness = Harness()
        let controls = GoToFieldControls(field: harness.field, goButton: nil)
        harness.field.focusReadError = InjectionError.axError(code: Self.axCannotCompleteCode)
        #expect(try await harness.wait.requestFocus(of: controls) == .unavailable)

        harness.field.focusReadError = InjectionError.panelGone
        #expect(try await harness.wait.requestFocus(of: controls) == .fieldGone)
    }

    @Test("待っている間にキャンセルされたら CancellationError を投げる")
    func cancelledWhileWaiting() async {
        let harness = Harness()
        harness.field.focusProvider = {
            cancelCurrentTask()
            return false
        }

        await #expect(throws: CancellationError.self) {
            try await harness.waitUntilFocused()
        }
    }

    @Test("探している間にキャンセルされたら、unavailable ではなく CancellationError を投げる")
    func cancelledWhileLookingUp() async {
        let harness = Harness()
        let suspension = Suspension()
        harness.locator.suspension = suspension
        let task = Task { _ = try await harness.waitUntilFocused() }

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
