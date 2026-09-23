import Testing

import OpenPathCore

@Suite("PathInjectionFlow: 正規化 → 主方式 → 副方式へのフォールバック → auto_confirm（DSN-001 §3〜§4）", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowTests {
    private static let rawPath = "~/Documents/../Documents/資料/"
    private static let normalizedPath = "/Users/me/Documents/資料"
    /// kAXErrorAttributeUnsupported
    private static let axAttributeUnsupportedCode: Int32 = -25_205
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    // MARK: - 主方式

    @Test("注入先を最初に 1 回だけ記録し、正規化したパスを主方式で貼り付ける。成功したら副方式は使わない")
    func primarySucceedsWithNormalizedPath() async throws {
        let harness = FlowHarness()

        try await harness.run(path: Self.rawPath)

        #expect(harness.log.events.first == .captureTarget)
        #expect(harness.targetGuard.captureCount == 1)
        #expect(harness.pasteboard.writes == [.transientText(Self.normalizedPath), .userClipboard])
        #expect(!harness.log.events.contains(.lookUpGoToField))
    }

    @Test("auto_confirm でなければ（既定）、移動だけして「開く」は探しも押しもしない（FR-INJECT-03）")
    func doesNotOpenByDefault() async throws {
        let harness = FlowHarness()

        try await harness.run(path: Self.rawPath, autoConfirm: false)

        #expect(!harness.log.events.contains(.lookUpOpenButton))
        #expect(harness.elementOperations.isEmpty)
    }

    @Test("auto_confirm なら Return の 300ms 後に「開く」を押し、その直後にペーストボードを戻す")
    func primaryWithAutoConfirmTimeline() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150))

        try await harness.run(path: Self.rawPath, autoConfirm: true)

        let tail = harness.log.entries.drop { $0.event != .key(.returnKey) }
        let expected: [InjectionEventLog.Entry] = [
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(250), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(550), event: .lookUpOpenButton),
            .init(time: .milliseconds(550), event: .press(element: "open")),
            .init(time: .milliseconds(550), event: .pasteboardWrite(.userClipboard)),
        ]
        #expect(Array(tail) == expected)
    }

    @Test("「開く」の押下でパネルが閉じても、成功として返す（.panelGone を投げない）")
    func succeedsWhenPanelClosesAfterOpen() async throws {
        let harness = FlowHarness()
        harness.openButton.pressError = InjectionError.panelGone
        harness.openButton.disappearsWhenActivated = true

        try await harness.run(path: Self.rawPath, autoConfirm: true)

        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test(
        "「開く」を押す前にパネルが消えたら、自動確定では panelGoneBeforeConfirm、そうでなければ panelGone を投げる",
        arguments: [
            (autoConfirm: true, expected: InjectionError.panelGoneBeforeConfirm),
            (autoConfirm: false, expected: InjectionError.panelGone),
        ]
    )
    func panelGoneBeforeOpen(outcome: (autoConfirm: Bool, expected: InjectionError)) async {
        let harness = FlowHarness()
        // ⌘A の直前の確認でパネルが消えている
        harness.targetGuard.invalidation = (fromCheck: 1, status: .gone)

        await #expect(throws: outcome.expected) {
            try await harness.run(path: Self.rawPath, autoConfirm: outcome.autoConfirm)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("自動確定で「開く」を探す時点でパネルが消えていたら、押していないので panelGoneBeforeConfirm を投げる")
    func panelGoneWhileLookingUpOpenButton() async {
        let harness = FlowHarness()
        harness.openButtonLocator.error = InjectionError.panelGone
        var thrown: (any Error)?

        do {
            try await harness.run(path: Self.rawPath, autoConfirm: true)
        } catch {
            thrown = error
        }

        #expect(thrown as? InjectionError == .panelGoneBeforeConfirm)
        #expect((thrown as? InjectionError)?.userMessage == "移動できませんでした（パネルが閉じられました）")
        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    // MARK: - 副方式へのフォールバック

    @Test("⌘⇧G のシートが出なければ副方式で入力欄に直接セットして「移動」を押す。ペーストボードには触れない")
    func fallsBackToDirectEntryWhenSheetDoesNotAppear() async throws {
        let harness = FlowHarness(sheetAppearsAt: nil)

        try await harness.run(path: Self.rawPath)

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.elementOperations == [
            .setValue(element: "path", value: Self.normalizedPath),
            .press(element: "go"),
        ])
        #expect(harness.log.events.last == .didSubmitGoToSheet(autoConfirm: false))
    }

    @Test("副方式でも auto_confirm なら「移動」の 300ms 後に「開く」を押す。全体は 1.5 秒の全体タイムアウトに収まる")
    func directEntryWithAutoConfirmTimeline() async throws {
        let harness = FlowHarness(sheetAppearsAt: nil)

        try await harness.run(path: Self.rawPath, autoConfirm: true)

        // 主方式は最後のシート確認（550ms）で見つからなければ、期限（600ms）を待たずに失敗を返す
        let tail = harness.log.entries.drop { $0.event != .lookUpGoToField }
        let expected: [InjectionEventLog.Entry] = [
            .init(time: .milliseconds(550), event: .lookUpGoToField),
            .init(time: .milliseconds(550), event: .setValue(element: "path", value: Self.normalizedPath)),
            .init(time: .milliseconds(550), event: .press(element: "go")),
            .init(time: .milliseconds(550), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(850), event: .lookUpOpenButton),
            .init(time: .milliseconds(850), event: .press(element: "open")),
        ]
        #expect(Array(tail) == expected)
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
    }

    @Test("副方式でも入力欄が見つからなければ timeout(waitSheet) を投げ、パレットに「⌘⇧G が開きません」を出す")
    func directEntryAlsoFailsAfterSheetTimeout() async {
        let harness = FlowHarness(sheetAppearsAt: nil)
        harness.goToFieldLocator.field = nil
        var thrown: (any Error)?

        do {
            try await harness.run(path: Self.rawPath)
        } catch {
            thrown = error
        }

        #expect(thrown as? InjectionError == .timeout(step: .waitSheet))
        #expect((thrown as? InjectionError)?.userMessage == "移動できませんでした（⌘⇧G が開きません）")
    }

    @Test("シートは出たがパスを書き込めない（waitPaste）ときも副方式で移動し、ペーストボードは元のまま")
    func fallsBackToDirectEntryWhenPasteFails() async throws {
        let harness = FlowHarness()
        harness.pasteboard.remainingWriteFailures = 1

        try await harness.run(path: Self.rawPath)

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.elementOperations.first == .setValue(element: "path", value: Self.normalizedPath))
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("waitPaste から副方式に切り替えても入力欄が無ければ、「パスの貼り付けに失敗」を出す")
    func directEntryAlsoFailsAfterPasteFailure() async {
        let harness = FlowHarness()
        harness.keyboard.failingKeyStrokes = [.paste]
        harness.goToFieldLocator.field = nil
        var thrown: (any Error)?

        do {
            try await harness.run(path: Self.rawPath)
        } catch {
            thrown = error
        }

        #expect(thrown as? InjectionError == .timeout(step: .waitPaste))
        #expect((thrown as? InjectionError)?.userMessage == "移動できませんでした（パスの貼り付けに失敗）")
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("副方式で値をセットできなければ（kAXErrorAttributeUnsupported）、「アクセシビリティ操作に失敗 (code)」を出す")
    func directEntrySetValueFailureMessage() async {
        let harness = FlowHarness(sheetAppearsAt: nil)
        harness.goToField.setValueError = InjectionError.axError(code: Self.axAttributeUnsupportedCode)
        var thrown: (any Error)?

        do {
            try await harness.run(path: Self.rawPath)
        } catch {
            thrown = error
        }

        #expect(thrown as? InjectionError == .axError(code: Self.axAttributeUnsupportedCode))
        #expect((thrown as? InjectionError)?.userMessage == "移動できませんでした（アクセシビリティ操作に失敗 (-25205)）")
    }

    @Test(
        "シート待ち・貼り付け以外の主方式の失敗では副方式を試さない",
        arguments: [
            InjectionError.panelGone,
            .axError(code: axCannotCompleteCode),
            .targetNotFrontmost,
        ]
    )
    func doesNotFallBackOnOtherErrors(error: InjectionError) async {
        let harness = FlowHarness()
        harness.sheetDetector.probeError = error

        await #expect(throws: error) {
            try await harness.run(path: Self.rawPath)
        }

        #expect(!harness.log.events.contains(.lookUpGoToField))
    }

    @Test("ペーストボードを戻せなかったときは、貼り付けの失敗があっても副方式を試さない（Return 前の失敗でも）")
    func doesNotFallBackWhenPasteboardRestoreFails() async {
        let harness = FlowHarness()
        harness.keyboard.failingKeyStrokes = [.selectAll]
        harness.pasteboard.onWrite = { [unowned pasteboard = harness.pasteboard] _ in
            // パスの書き込みは成功させ、元の内容への書き戻しを失敗させる
            pasteboard.remainingWriteFailures = 1
        }

        await #expect(throws: InjectionError.pasteboardRestoreFailed) {
            try await harness.run(path: Self.rawPath)
        }

        #expect(!harness.log.events.contains(.lookUpGoToField))
    }

    // MARK: - 注入先

    @Test("注入先を記録できなければ（最前面にパネルが無い）、何も操作せずにそのエラーを投げる")
    func captureFailureTouchesNothing() async {
        let harness = FlowHarness()
        harness.targetGuard.captureError = InjectionError.panelGone

        await #expect(throws: InjectionError.panelGone) {
            try await harness.run(path: Self.rawPath)
        }

        #expect(harness.log.events == [.captureTarget])
    }

    @Test("注入先の記録が期限で打ち切られたら axError(cannotComplete) を投げる")
    func captureCutOffIsCannotComplete() async {
        let harness = FlowHarness()
        harness.targetGuard.captureError = ScanCutoff.Reached()

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run(path: Self.rawPath)
        }
    }

    @Test("別のアプリ・ウィンドウに切り替わったら、送らずに targetNotFrontmost を投げ、パレットには理由を出す")
    func targetNotFrontmostMessage() async {
        let harness = FlowHarness()
        harness.targetGuard.invalidation = (fromCheck: 1, status: .notFrontmost)
        var thrown: (any Error)?

        do {
            try await harness.run(path: Self.rawPath)
        } catch {
            thrown = error
        }

        #expect(thrown as? InjectionError == .targetNotFrontmost)
        #expect((thrown as? InjectionError)?.userMessage == "移動できませんでした（パネルが最前面でなくなりました）")
        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    // MARK: - キャンセルと直列化

    @Test("主方式のシート待ちでキャンセルされたら、副方式を試さずに CancellationError を投げる")
    func cancellationDuringPrimaryDoesNotFallBack() async {
        let harness = FlowHarness(sheetAppearsAt: nil)
        let suspension = Suspension()
        harness.sheetDetector.checkSuspension = suspension
        let task = harness.startRun(path: Self.rawPath)

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!harness.log.events.contains(.lookUpGoToField))
    }

    @Test("前の注入が副方式を終えるまで、次の注入は注入先の記録もキー操作も始めない")
    func serializesInjectionsIncludingDirectEntry() async throws {
        let harness = FlowHarness(sheetAppearsAt: nil)
        let suspension = Suspension()
        harness.goToFieldLocator.suspension = suspension
        let first = harness.startRun(path: Self.rawPath)
        await suspension.waitUntilSuspended()

        harness.goToFieldLocator.suspension = nil
        let second = harness.startRun(path: "/Users/me/repos")
        await harness.drainMainActor()
        #expect(harness.targetGuard.captureCount == 1)

        suspension.resume()
        try await first.value
        try await second.value
        #expect(harness.targetGuard.captureCount == 2)
    }
}
