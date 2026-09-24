import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: 失敗とキャンセルでもペーストボードを戻す", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerFailureTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let anotherPath = "/Users/me/Documents/資料"
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204

    private static func isCancellation(_ result: Result<Void, any Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        return error is CancellationError
    }

    // MARK: - 失敗

    @Test("注入先を特定できなければ、そのエラーを投げ、ペーストボードにもキーにも触れない")
    func probeFailureTouchesNothing() async {
        let harness = SequencerHarness()
        harness.sheetDetector.probeError = InjectionError.axError(code: Self.axCannotCompleteCode)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.events == [.makeProbe])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("注入先の特定や判定が InjectionError 以外で失敗したら、⌘⇧G が開かない扱いにする")
    func unknownDetectorFailureIsWaitSheet() async {
        let probeFailing = SequencerHarness()
        probeFailing.sheetDetector.probeError = AdapterFailure()
        let checkFailing = SequencerHarness()
        checkFailing.sheetDetector.checkError = AdapterFailure()

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await probeFailing.run(path: Self.path)
        }
        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await checkFailing.run(path: Self.path)
        }
        #expect(checkFailing.pasteboard.writes.isEmpty)
    }

    @Test("⌘⇧G を送れなければ timeout(waitSheet) を投げ、ペーストボードに触れない")
    func goToFolderPostFailure() async {
        let harness = SequencerHarness()
        harness.keyboard.failingKeyStrokes = [.goToFolder]

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        #expect(!harness.log.events.contains { if case .sheetCheck = $0 { true } else { false } })
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test(
        "⌘A / ⌘V / Return を送れなければ timeout(waitPaste) を投げ、以降のキーを送らずにペーストボードを戻す",
        arguments: [InjectionKeyStroke.selectAll, .paste, .returnKey]
    )
    func pasteStepPostFailure(failing: InjectionKeyStroke) async {
        let harness = SequencerHarness()
        harness.keyboard.failingKeyStrokes = [failing]

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        let allKeys: [InjectionKeyStroke] = [.goToFolder, .selectAll, .paste, .returnKey]
        let sentKeys = Array(allKeys.prefix { $0 != failing })
        #expect(harness.log.keyStrokes == sentKeys)
        #expect(harness.pasteboard.writes == [.transientText(Self.path), .userClipboard])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("パスを書き込めなければ timeout(waitPaste) を投げ、貼り付けずに元の内容を残す")
    func pasteboardWriteFailure() async {
        let harness = SequencerHarness()
        harness.pasteboard.remainingWriteFailures = 1

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("ステップ 8 のフックが投げたエラーはそのまま伝え、すぐにペーストボードを戻す")
    func hookFailureRestoresImmediately() async throws {
        let hookError = InjectionError.axError(code: Self.axCannotCompleteCode)
        let harness = SequencerHarness()
        harness.hooks.submitError = hookError

        await #expect(throws: hookError) {
            try await harness.run(path: Self.path)
        }

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(harness.log.entries.last == .init(time: returnTime, event: .pasteboardWrite(.userClipboard)))
    }

    // MARK: - ペーストボードの復元の失敗

    @Test("注入が成功しても、ペーストボードを戻せなければ pasteboardRestoreFailed を投げる")
    func restoreFailureAfterSuccess() async {
        let harness = SequencerHarness()
        harness.hooks.onSubmit = { harness.pasteboard.remainingWriteFailures = 1 }

        await #expect(throws: InjectionError.pasteboardRestoreFailed) {
            try await harness.run(path: Self.path)
        }
    }

    @Test("注入が失敗し、ペーストボードも戻せなければ、元のエラーより pasteboardRestoreFailed を優先する")
    func restoreFailureTakesPriorityOverInjectionFailure() async {
        let harness = SequencerHarness()
        harness.keyboard.failingKeyStrokes = [.returnKey]
        harness.keyboard.onPost = { keyStroke in
            if keyStroke == .paste {
                harness.pasteboard.remainingWriteFailures = 1
            }
        }

        await #expect(throws: InjectionError.pasteboardRestoreFailed) {
            try await harness.run(path: Self.path)
        }
    }

    @Test("他者の書き込みを優先して戻さなかった場合は、失敗経路でも元のエラーをそのまま投げる")
    func skippedRestoreKeepsOriginalError() async {
        let harness = SequencerHarness()
        harness.keyboard.failingKeyStrokes = [.returnKey]
        harness.keyboard.onPost = { keyStroke in
            if keyStroke == .paste {
                harness.pasteboard.simulateExternalWrite(.newerUserCopy)
            }
        }

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }
        #expect(harness.pasteboard.contents == .newerUserCopy)
    }

    @Test("ペーストボードの退避の途中で他者が書き換えたら、ペーストボードに書き込まずに timeout(waitPaste) を投げる（副方式へ）")
    func changeDuringCaptureIsWaitPaste() async {
        let harness = SequencerHarness()
        harness.pasteboard.onDataRead = { _ in
            harness.pasteboard.onDataRead = nil
            harness.pasteboard.simulateExternalWrite(.newerUserCopy)
        }

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.pasteboard.contents == .newerUserCopy)
        #expect(harness.log.keyStrokes == [.goToFolder])
    }

    @Test("元のクリップボードが機密なら、失敗経路でも戻さずに空にし、元のエラーをそのまま投げる")
    func concealedClipboardIsClearedOnFailure() async {
        let harness = SequencerHarness(clipboard: .concealedPassword)
        harness.keyboard.failingKeyStrokes = [.returnKey]

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }
        #expect(harness.pasteboard.contents == .empty)
        #expect(harness.pasteboard.writes == [.transientText(Self.path), .empty])
    }

    // MARK: - キャンセル

    @Test("開始前にキャンセルされていたら、何もせずに CancellationError を投げる")
    func cancelledBeforeStart() async {
        let harness = SequencerHarness()
        let task = Task { [sequencer = harness.sequencer] in
            cancelCurrentTask()
            try await sequencer.run(path: Self.path, autoConfirm: false)
        }

        #expect(Self.isCancellation(await task.result))
        #expect(harness.log.events.isEmpty)
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("シートの判定中にキャンセルされたら、走査が打ち切り条件でそれを検知し、キャンセルとして戻る")
    func cancellationIsVisibleToRunningScan() async throws {
        let harness = SequencerHarness()
        let suspension = Suspension()
        harness.sheetDetector.checkSuspension = suspension
        harness.sheetDetector.suspendedCheckResult = true
        let task = harness.startRun(path: Self.path)
        await suspension.waitUntilSuspended()
        let cutoff = try #require(harness.sheetDetector.suspendedCheckCutoff)
        #expect(!cutoff.isReached)

        task.cancel()

        // AX の走査は Task の外（axQueue）で同期に進むため、キャンセルは打ち切り条件を通して走査に伝わる
        #expect(cutoff.isReached)
        suspension.resume()
        #expect(Self.isCancellation(await task.result))
        #expect(harness.log.events.last == .scanCutOff)
        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("判定が打ち切り条件を見ずにシートの出現を返しても、キャンセル済みなら貼り付けない")
    func cancelledWhileCheckingSheetWithoutCutoff() async {
        let harness = SequencerHarness()
        let suspension = Suspension()
        harness.sheetDetector.checkSuspension = suspension
        harness.sheetDetector.suspendedCheckResult = true
        harness.sheetDetector.checksCutoffAfterSuspension = false
        let task = harness.startRun(path: Self.path)
        await suspension.waitUntilSuspended()

        task.cancel()
        suspension.resume()

        #expect(Self.isCancellation(await task.result))
        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("⌘V の直後にキャンセルされたら、Return を送らずにすぐペーストボードを戻す")
    func cancelledAfterPaste() async {
        let harness = SequencerHarness()
        harness.keyboard.onPost = { keyStroke in
            if keyStroke == .paste {
                cancelCurrentTask()
            }
        }

        let task = harness.startRun(path: Self.path)

        #expect(Self.isCancellation(await task.result))
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste])
        let pasteTime = harness.log.entries.first { $0.event == .key(.paste) }?.time
        #expect(harness.log.entries.last == .init(time: pasteTime ?? .zero, event: .pasteboardWrite(.userClipboard)))
    }

    @Test("Return 後の復元待ちでキャンセルされたら、200ms を待たずにすぐ戻す")
    func cancelledWhileWaitingToRestore() async {
        let harness = SequencerHarness()
        let suspension = Suspension()
        harness.hooks.submitSuspension = suspension
        let task = harness.startRun(path: Self.path)
        await suspension.waitUntilSuspended()

        task.cancel()
        suspension.resume()

        #expect(Self.isCancellation(await task.result))
        let returnTime = harness.log.entries.first { $0.event == .key(.returnKey) }?.time
        #expect(harness.log.entries.last == .init(time: returnTime ?? .zero, event: .pasteboardWrite(.userClipboard)))
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("キャンセル済みの注入が後始末を終えるまで、次の注入はキーもペーストボードも触らない")
    func nextRunWaitsForCancelledRunToRestore() async throws {
        let harness = SequencerHarness()
        let suspension = Suspension()
        harness.hooks.submitSuspension = suspension
        let first = harness.startRun(path: Self.path)
        await suspension.waitUntilSuspended()
        first.cancel()
        harness.hooks.submitSuspension = nil

        let second = harness.startRun(path: Self.anotherPath)
        await harness.drainMainActor()

        #expect(harness.log.events.filter { $0 == .makeProbe }.count == 1)
        #expect(harness.pasteboard.contents == .transientText(Self.path))

        suspension.resume()

        #expect(Self.isCancellation(await first.result))
        try await second.value
        // 2 回目の退避に 1 回目のパスが混ざらず、最終的にユーザーの内容へ戻る
        #expect(harness.pasteboard.writes == [
            .transientText(Self.path), .userClipboard,
            .transientText(Self.anotherPath), .userClipboard,
        ])
        #expect(harness.pasteboard.contents == .userClipboard)
    }
}
