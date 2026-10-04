import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: 移動先シートが既に開いていれば ⌘⇧G を送らずにその入力欄へ注入する（Issue #95）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerPreopenedSheetTests {
    private static let path = "/Users/me/Library"

    /// ⌘⇧G を送る前から移動先シートが開いている状態。⌘⇧G を送っても新しいシートは出ない（macOS 27 で確認）。
    private static func makeHarness() -> SequencerHarness {
        let harness = SequencerHarness(sheetAppearsAt: nil, checksBeforeSubmit: true, waitsForFieldFocus: true)
        harness.sheetDetector.isSheetAlreadyShown = true
        return harness
    }

    @Test("⌘⇧G を送らず、開いているシートの入力欄のフォーカスを確かめてから ⌘A / ⌘V → 確定前の確認 → Return")
    func injectsIntoPreopenedSheetWithoutCommandShiftG() async throws {
        let harness = Self.makeHarness()

        try await harness.run(path: Self.path)

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .zero, event: .makeProbe),
            .init(time: .zero, event: .prepareForKeyEvents),
            .init(time: .zero, event: .pasteboardWrite(.transientText(Self.path))),
            .init(time: .zero, event: .key(.selectAll)),
            .init(time: .zero, event: .key(.paste)),
            // 貼り付けたパスが入力欄に入ったのを確かめたため、Return の前に戻す
            .init(time: .milliseconds(100), event: .pasteboardWrite(.userClipboard)),
            .init(time: .milliseconds(100), event: .key(.returnKey)),
            .init(time: .milliseconds(100), event: .didSubmitGoToSheet(autoConfirm: false)),
        ]
        #expect(harness.log.entries == expected)
        #expect(harness.goToField.currentValue == Self.path)
        #expect(harness.pasteboard.contents == .userClipboard)
        // 開いているシートの入力欄を探すのは 1 回だけ（フォーカス待ちと確定前の確認は、見つけた入力欄を使う）
        #expect(harness.goToFieldLocator.lookupCount == 1)
    }

    @Test("キーを送る直前ごとの注入先の確認は従来どおり（⌘A の前に最前面でなくなっていたら送らずにペーストボードを戻す）")
    func checksTargetBeforeEveryKey() async {
        let harness = Self.makeHarness()
        harness.targetGuard.invalidation = (fromCheck: 0, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.isEmpty)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("開いているシートの入力欄にフォーカスが来なければ、ペーストボードに触れずに timeout(waitPaste) を投げる（副方式へ）")
    func fallsBackWhenFocusNeverArrives() async {
        let harness = Self.makeHarness()
        harness.goToField.hasFocus = false

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.isEmpty)
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.clock.elapsed == .milliseconds(250))
    }

    @Test(
        "開いているシートの入力欄を AXIdentifier で特定できなければ、従来どおり ⌘⇧G を送る",
        arguments: [GoToFieldEvidence.goButton, .placeholder]
    )
    func sendsCommandShiftGWhenFieldIsNotIdentified(evidence: GoToFieldEvidence) async throws {
        let harness = Self.makeHarness()
        harness.goToFieldLocator.evidence = evidence
        harness.sheetDetector.appearsAt = .milliseconds(150)

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("開いているシートの入力欄が見つからなければ、従来どおり ⌘⇧G を送る")
    func sendsCommandShiftGWhenFieldIsMissing() async throws {
        let harness = Self.makeHarness()
        harness.goToFieldLocator.field = nil
        harness.sheetDetector.appearsAt = .milliseconds(150)

        // 入力欄が見つからないままでは、Return の後にシートが閉じたことも確かめられないため、成功にはしない（Issue #95）
        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.first == .goToFolder)
    }

    @Test("開いているシートの入力欄を探せなければ（AX の失敗）、従来どおり ⌘⇧G を送る")
    func sendsCommandShiftGWhenLookupFails() async throws {
        let harness = Self.makeHarness()
        harness.goToFieldLocator.error = InjectionError.axError(code: -25_204)
        harness.sheetDetector.appearsAt = .milliseconds(150)

        // 探せないままでは、Return の後にシートが閉じたことも確かめられないため、成功にはしない（Issue #95）
        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.first == .goToFolder)
    }

    @Test("入力欄のフォーカスを待たない構成では、開いているシートを使わず従来どおり ⌘⇧G を送る")
    func sendsCommandShiftGWithoutFieldFocusWait() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150))
        harness.sheetDetector.isSheetAlreadyShown = true

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("開いているシートの入力欄を探している間にキャンセルされたら、キーもペーストボードも使わずに CancellationError を投げる")
    func cancelledWhileLocatingPreopenedField() async {
        let harness = Self.makeHarness()
        let suspension = Suspension()
        harness.goToFieldLocator.suspension = suspension
        let task = harness.startRun(path: Self.path)

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(harness.log.keyStrokes.isEmpty)
        #expect(harness.pasteboard.writes.isEmpty)
    }
}

