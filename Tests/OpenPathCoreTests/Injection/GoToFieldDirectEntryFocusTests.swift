import Testing

import OpenPathCore

@Suite("GoToFieldDirectEntry: Return の前に移動先シートの入力欄のフォーカスを待つ（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFieldDirectEntryFocusTests {
    private static let path = "/Users/me/Library"
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let field: PanelElementFake
        let locator: GoToFieldLocatorFake
        let targetGuard: TargetGuardFake
        let keyboard: KeyboardSpy
        let hooks: HooksSpy
        let entry: GoToFieldDirectEntry

        /// 「移動」ボタンの無い移動先シート（macOS 13 以降）。
        init() {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            field = PanelElementFake("path", log: log)
            locator = GoToFieldLocatorFake(clock: clock, log: log)
            locator.field = field
            targetGuard = TargetGuardFake(log: log)
            targetGuard.logsChecks = true
            keyboard = KeyboardSpy(log: log)
            hooks = HooksSpy(clock: clock, log: log)
            entry = GoToFieldDirectEntry(
                locator: locator,
                targetGuard: targetGuard,
                keyboard: keyboard,
                prepareForKeyEvents: hooks.hooks.prepareForKeyEvents,
                fieldFocus: GoToFieldFocusWait(locator: locator, clock: clock),
                didSubmit: hooks.hooks.didSubmitGoToSheet,
                clock: clock
            )
        }

        func run() async throws {
            try await entry.run(path: GoToFieldDirectEntryFocusTests.path, autoConfirm: false, fallingBackFrom: .timeout(step: .waitPaste))
        }

        /// この経過時間以降の読み取りで、入力欄がフォーカスを持つことにする。nil なら持たない。
        func focusArrives(at time: Duration?) {
            field.focusProvider = { [clock] in
                time.map { clock.elapsed >= $0 } ?? false
            }
        }

        var returnTime: Duration? {
            log.entries.first { $0.event == .key(.returnKey) }?.time
        }
    }

    @Test("入力欄がフォーカスを持っていれば、待たずに Return を送る")
    func sendsReturnImmediatelyWhenFocused() async throws {
        let harness = Harness()

        try await harness.run()

        #expect(harness.log.events == [
            .lookUpGoToField,
            .targetCheck,
            .setValue(element: "path", value: Self.path),
            .targetCheck,
            .prepareForKeyEvents,
            .targetCheck,
            .key(.returnKey),
            .didSubmitGoToSheet(autoConfirm: false),
        ])
        #expect(harness.field.focusReadCount == 1)
        #expect(harness.returnTime == .zero)
    }

    @Test("フォーカスが遅れて来たら、来てから Return を送る")
    func waitsForFocusBeforeReturn() async throws {
        let harness = Harness()
        harness.focusArrives(at: .milliseconds(100))

        try await harness.run()

        #expect(harness.returnTime == .milliseconds(100))
        #expect(!harness.log.events.contains(.focusField(element: "path")))
    }

    @Test("250ms 待ってもフォーカスが来なければ、注入先を確かめてから AX でフォーカスを与え、Return を送る")
    func requestsFocusWhenItNeverArrives() async throws {
        let harness = Harness()
        harness.focusArrives(at: nil)

        try await harness.run()

        let tail = harness.log.entries.drop { $0.event != .prepareForKeyEvents }
        #expect(Array(tail) == [
            .init(time: .zero, event: .prepareForKeyEvents),
            .init(time: .milliseconds(250), event: .targetCheck),
            .init(time: .milliseconds(250), event: .focusField(element: "path")),
            .init(time: .milliseconds(250), event: .targetCheck),
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(250), event: .didSubmitGoToSheet(autoConfirm: false)),
        ])
    }

    @Test("AX でフォーカスを与えられなくても、従来どおり Return は送る")
    func sendsReturnEvenIfFocusRequestFails() async throws {
        let harness = Harness()
        harness.focusArrives(at: nil)
        harness.field.focusRequestError = InjectionError.axError(code: Self.axCannotCompleteCode)

        try await harness.run()

        #expect(harness.log.keyStrokes == [.returnKey])
        #expect(harness.log.events.last == .didSubmitGoToSheet(autoConfirm: false))
    }

    @Test("フォーカスを与える前の確認で注入先が無効なら、フォーカスも Return も送らずに投げる")
    func stopsBeforeFocusRequestWhenTargetIsLost() async {
        let harness = Harness()
        harness.focusArrives(at: nil)
        // 0: 値のセットの前、1: 確定の前、2: フォーカスを与える前
        harness.targetGuard.invalidation = (fromCheck: 2, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run()
        }

        #expect(!harness.log.events.contains(.focusField(element: "path")))
        #expect(harness.log.keyStrokes.isEmpty)
    }

    @Test("Return の前に入力欄が消えていたら（移動先シートが閉じた）、Return を送らずに timeout(waitPaste) を投げる")
    func doesNotSendReturnWhenFieldDisappears() async {
        let harness = Harness()
        harness.field.focusReadError = InjectionError.panelGone

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run()
        }

        #expect(harness.log.keyStrokes.isEmpty)
        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
    }

    @Test("入力欄が消えたときにパネルごと閉じていたら、panelGone を投げる")
    func reportsPanelGoneWhenPanelClosesBeforeReturn() async {
        let harness = Harness()
        harness.field.focusReadError = InjectionError.panelGone
        harness.targetGuard.invalidation = (fromCheck: 2, status: .gone)

        await #expect(throws: InjectionError.panelGone) {
            try await harness.run()
        }

        #expect(harness.log.keyStrokes.isEmpty)
    }

    @Test("フォーカスを読めなければ、待たずに従来どおり Return を送る")
    func sendsReturnWhenFocusCannotBeRead() async throws {
        let harness = Harness()
        harness.field.focusReadError = InjectionError.axError(code: Self.axCannotCompleteCode)

        try await harness.run()

        #expect(harness.returnTime == .zero)
        #expect(!harness.log.events.contains(.focusField(element: "path")))
    }

    @Test("「移動」ボタンを AXPress で押すときはキー入力を使わないため、フォーカスを待たない")
    func doesNotWaitForFocusWhenPressingGoButton() async throws {
        let harness = Harness()
        harness.locator.goButton = PanelElementFake("go", log: harness.log)
        harness.focusArrives(at: nil)

        try await harness.run()

        #expect(harness.field.focusReadCount == 0)
        #expect(harness.log.events.contains(.press(element: "go")))
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("フォーカスを待っている間にキャンセルされたら、Return を送らずに CancellationError を投げる")
    func cancelledWhileWaitingForFocus() async {
        let harness = Harness()
        harness.field.focusProvider = {
            cancelCurrentTask()
            return false
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run()
        }

        #expect(harness.log.keyStrokes.isEmpty)
    }
}
