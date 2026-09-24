import Testing

import OpenPathCore

@Suite("GoToFieldDirectEntry: 副方式（AX 直接セット、DSN-001 §3.2）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFieldDirectEntryTests {
    private static let path = "/Users/me/Documents/資料"
    /// kAXErrorFailure
    private static let axFailureCode: Int32 = -25_200
    /// kAXErrorAttributeUnsupported
    private static let axAttributeUnsupportedCode: Int32 = -25_205
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let field: PanelElementFake
        let goButton: PanelElementFake
        let locator: GoToFieldLocatorFake
        let targetGuard: TargetGuardFake
        let keyboard: KeyboardSpy
        let hooks: HooksSpy
        let entry: GoToFieldDirectEntry

        /// - Parameter checksBeforeSubmit: 確定の前に入力欄の値と候補の選択を確かめるか（`GoToSheetSubmitGate`）。
        init(checksBeforeSubmit: Bool = false) {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            field = PanelElementFake("path", log: log)
            goButton = PanelElementFake("go", log: log)
            locator = GoToFieldLocatorFake(clock: clock, log: log)
            locator.field = field
            locator.goButton = goButton
            targetGuard = TargetGuardFake(log: log)
            targetGuard.logsChecks = true
            keyboard = KeyboardSpy(log: log)
            hooks = HooksSpy(clock: clock, log: log)
            entry = GoToFieldDirectEntry(
                locator: locator,
                targetGuard: targetGuard,
                keyboard: keyboard,
                prepareForKeyEvents: hooks.hooks.prepareForKeyEvents,
                submitGate: checksBeforeSubmit
                    ? GoToSheetSubmitGate(
                        locator: locator,
                        normalizer: InjectionPathNormalizer(homeDirectory: "/Users/me"),
                        clock: clock
                    )
                    : nil,
                didSubmit: hooks.hooks.didSubmitGoToSheet,
                timing: .standard,
                clock: clock
            )
        }

        func run(
            autoConfirm: Bool = false,
            fallingBackFrom primaryError: InjectionError = .timeout(step: .waitSheet)
        ) async throws {
            try await entry.run(path: GoToFieldDirectEntryTests.path, autoConfirm: autoConfirm, fallingBackFrom: primaryError)
        }

        /// 入力欄・ボタンへの AX 操作（値のセット・押下・確定）。
        var elementOperations: [InjectionEventLog.Event] {
            log.events.filter { event in
                switch event {
                case .setValue, .press, .confirmField: true
                default: false
                }
            }
        }
    }

    @Test("入力欄を探し、値を直接セットして「移動」を押し、ステップ 8 のフックを呼ぶ。各操作の直前に注入先を確かめる")
    func setsValueAndPressesGoButton() async throws {
        let harness = Harness()

        try await harness.run(autoConfirm: true)

        #expect(harness.log.events == [
            .lookUpGoToField,
            .targetCheck,
            .setValue(element: "path", value: Self.path),
            .targetCheck,
            .press(element: "go"),
            .didSubmitGoToSheet(autoConfirm: true),
        ])
    }

    @Test("「移動」ボタンが無ければ（macOS 13 以降の移動先シート）、パレットにキーを手放させてから Return を送る。入力欄の確定（kAXConfirmAction）は使わない")
    func sendsReturnWithoutGoButton() async throws {
        let harness = Harness()
        harness.locator.goButton = nil

        try await harness.run(autoConfirm: true)

        // macOS 27 の移動先シートの入力欄は kAXConfirmAction に成功を返すが移動しない（Issue #74）
        #expect(harness.log.events == [
            .lookUpGoToField,
            .targetCheck,
            .setValue(element: "path", value: Self.path),
            .targetCheck,
            .prepareForKeyEvents,
            .targetCheck,
            .key(.returnKey),
            .didSubmitGoToSheet(autoConfirm: true),
        ])
    }

    @Test("「移動」ボタンが無く Return も送れなければ、入力欄を確定する（kAXConfirmAction）")
    func confirmsFieldWhenReturnCannotBePosted() async throws {
        let harness = Harness()
        harness.locator.goButton = nil
        harness.keyboard.failingKeyStrokes = [.returnKey]

        try await harness.run()

        #expect(harness.elementOperations == [
            .setValue(element: "path", value: Self.path),
            .confirmField(element: "path"),
        ])
        #expect(harness.log.events.last == .didSubmitGoToSheet(autoConfirm: false))
    }

    @Test("Return を送る直前（パレットにキーを手放させた後）に注入先が無効になっていたら、Return を送らずに投げる")
    func stopsBeforeReturnWhenTargetIsLost() async {
        let harness = Harness()
        harness.locator.goButton = nil
        harness.targetGuard.invalidation = (fromCheck: 2, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run()
        }

        #expect(harness.log.keyStrokes.isEmpty)
        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
    }

    @Test("確定前の確認: セットした値が入力欄に入っていれば、待たずに「移動」を押す")
    func checksFieldBeforeSubmitting() async throws {
        let harness = Harness(checksBeforeSubmit: true)

        try await harness.run()

        #expect(harness.elementOperations == [
            .setValue(element: "path", value: Self.path),
            .press(element: "go"),
        ])
        #expect(harness.field.valueReadCount == 1)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("確定前の確認: セットした値が入力欄に入らなければ、確定せずに timeout(waitPaste) を投げる")
    func doesNotSubmitWhenFieldKeepsOtherValue() async {
        let harness = Harness(checksBeforeSubmit: true)
        harness.field.valueProvider = { "/Users/me/前回の場所" }

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run()
        }

        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
        #expect(harness.log.keyStrokes.isEmpty)
        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
    }

    @Test("確定前の確認: 候補リストが前の値の候補を選んだままなら、移動先に追いつくまで待ってから確定する")
    func waitsForSuggestionListBeforeSubmitting() async throws {
        let harness = Harness(checksBeforeSubmit: true)
        harness.locator.goButton = nil
        let suggestions = SuggestionListFake()
        suggestions.selectedPathProvider = { [clock = harness.clock] in
            clock.elapsed >= .milliseconds(100) ? Self.path : "/Users/me/前回の場所"
        }
        harness.locator.suggestionList = suggestions

        try await harness.run()

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(100))
    }

    @Test(
        "入力欄が見つからなければ、主方式の失敗をそのまま投げる（文言を主方式の失敗理由にするため）",
        arguments: [InjectionError.timeout(step: .waitSheet), .timeout(step: .waitPaste)]
    )
    func rethrowsPrimaryErrorWhenFieldIsMissing(primaryError: InjectionError) async {
        let harness = Harness()
        harness.locator.field = nil

        await #expect(throws: primaryError) {
            try await harness.run(fallingBackFrom: primaryError)
        }

        #expect(harness.elementOperations.isEmpty)
        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
    }

    @Test("探すのが 300ms を超えたら打ち切り、主方式の失敗を投げる")
    func lookupCutOffByDeadline() async {
        let harness = Harness()
        harness.locator.lookupLatency = .milliseconds(400)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run()
        }

        #expect(harness.log.events.contains(.scanCutOff))
        #expect(harness.elementOperations.isEmpty)
        #expect(harness.clock.elapsed == .milliseconds(300))
    }

    @Test(
        "注入先を特定できなければ（パネルが消えた・AX の失敗）、そのエラーを投げる",
        arguments: [InjectionError.panelGone, .axError(code: axCannotCompleteCode)]
    )
    func propagatesLookupInjectionError(error: InjectionError) async {
        let harness = Harness()
        harness.locator.error = error

        await #expect(throws: error) {
            try await harness.run()
        }
    }

    @Test("探すのが InjectionError 以外で失敗したら、主方式の失敗を投げる")
    func unknownLookupFailureIsPrimaryError() async {
        let harness = Harness()
        harness.locator.error = AdapterFailure()

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(fallingBackFrom: .timeout(step: .waitPaste))
        }
    }

    @Test("値をセットできなければ（kAXErrorAttributeUnsupported 等）、その axError を投げて押さない")
    func throwsWhenValueCannotBeSet() async {
        let harness = Harness()
        harness.field.setValueError = InjectionError.axError(code: Self.axAttributeUnsupportedCode)

        await #expect(throws: InjectionError.axError(code: Self.axAttributeUnsupportedCode)) {
            try await harness.run()
        }

        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
    }

    @Test("値のセットが InjectionError 以外で失敗したら axError(failure) を投げる")
    func unknownSetValueFailureIsAXFailure() async {
        let harness = Harness()
        harness.field.setValueError = AdapterFailure()

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.run()
        }
    }

    @Test(
        "操作の直前の確認で注入先が無効なら、その操作と以降の操作をせずに投げる",
        arguments: [0, 1], [
            (status: InjectionTargetStatus.notFrontmost, error: InjectionError.targetNotFrontmost),
            (status: InjectionTargetStatus.gone, error: InjectionError.panelGone),
        ]
    )
    func stopsWhenTargetIsLost(failingCheck: Int, lost: (status: InjectionTargetStatus, error: InjectionError)) async {
        let harness = Harness()
        harness.targetGuard.invalidation = (fromCheck: failingCheck, status: lost.status)
        let operations: [InjectionEventLog.Event] = [
            .setValue(element: "path", value: Self.path),
            .press(element: "go"),
        ]

        await #expect(throws: lost.error) {
            try await harness.run()
        }

        #expect(harness.elementOperations == Array(operations.prefix(failingCheck)))
    }

    @Test("「移動」の押下が失敗し、ボタンが残っていれば axError を投げ、フックを呼ばない")
    func throwsWhenGoButtonPressFails() async {
        let harness = Harness()
        harness.goButton.pressError = InjectionError.axError(code: Self.axCannotCompleteCode)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run()
        }

        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
    }

    @Test("「移動」の押下が失敗を返しても、ボタンが消えていれば（シートが閉じた）届いたものとして続ける")
    func continuesWhenGoButtonDisappears() async throws {
        let harness = Harness()
        harness.goButton.pressError = InjectionError.panelGone
        harness.goButton.disappearsWhenActivated = true

        try await harness.run()

        #expect(harness.log.events.last == .didSubmitGoToSheet(autoConfirm: false))
    }

    @Test("Return を送れず、入力欄の確定も失敗し、入力欄が残っていれば axError を投げる")
    func throwsWhenConfirmFails() async {
        let harness = Harness()
        harness.locator.goButton = nil
        harness.keyboard.failingKeyStrokes = [.returnKey]
        harness.field.confirmError = InjectionError.axError(code: Self.axCannotCompleteCode)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run()
        }
    }

    @Test("ステップ 8 のフック（auto_confirm）が投げたエラーはそのまま伝える")
    func propagatesHookError() async {
        let harness = Harness()
        harness.hooks.submitError = InjectionError.axError(code: Self.axFailureCode)

        await #expect(throws: InjectionError.axError(code: Self.axFailureCode)) {
            try await harness.run(autoConfirm: true)
        }
    }

    @Test("開始前にキャンセルされていたら、何もせずに CancellationError を投げる")
    func cancelledBeforeStart() async {
        let harness = Harness()
        let task = Task { [entry = harness.entry] in
            cancelCurrentTask()
            try await entry.run(path: Self.path, autoConfirm: false, fallingBackFrom: .timeout(step: .waitSheet))
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(harness.log.events.isEmpty)
    }

    @Test("探している最中にキャンセルされたら、走査が打ち切り条件でそれを検知し、値をセットせずに CancellationError を投げる")
    func cancelledWhileLookingUp() async {
        let harness = Harness()
        let suspension = Suspension()
        harness.locator.suspension = suspension
        let task = Task { [entry = harness.entry] in
            try await entry.run(path: Self.path, autoConfirm: false, fallingBackFrom: .timeout(step: .waitSheet))
        }

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(harness.elementOperations.isEmpty)
    }
}
