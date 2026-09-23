import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: キーを送る直前ごとに注入先を確かめる（別のアプリへの誤送出の防止）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerTargetGuardTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    /// 主方式が送るキー（送る順）。
    nonisolated private static let keyStrokes: [InjectionKeyStroke] = [.goToFolder, .selectAll, .paste, .returnKey]
    /// kAXErrorCannotComplete
    nonisolated private static let axCannotCompleteCode: Int32 = -25_204

    @Test("⌘⇧G・⌘A・⌘V・Return を送る直前ごとに、注入先がまだ有効かを確かめる")
    func checksTargetImmediatelyBeforeEachKey() async throws {
        let harness = SequencerHarness()
        harness.targetGuard.logsChecks = true

        try await harness.run(path: Self.path)

        let events = harness.log.events
        let keyIndices = events.indices.filter { if case .key = events[$0] { true } else { false } }
        #expect(keyIndices.count == Self.keyStrokes.count)
        for keyIndex in keyIndices {
            #expect(events[keyIndex - 1] == .targetCheck, "\(events[keyIndex]) の直前に確認していない")
        }
        #expect(harness.targetGuard.checkCount == Self.keyStrokes.count)
    }

    @Test(
        "確認で注入先が無効になったら、そのキーと以降のキーを送らずに投げ、ペーストボードは元に戻す",
        arguments: 0..<keyStrokes.count, [
            (status: InjectionTargetStatus.notFrontmost, error: InjectionError.targetNotFrontmost),
            (status: InjectionTargetStatus.gone, error: InjectionError.panelGone),
        ]
    )
    func stopsSendingKeysWhenTargetIsLost(failingCheck: Int, lost: (status: InjectionTargetStatus, error: InjectionError)) async {
        let harness = SequencerHarness()
        harness.targetGuard.invalidation = (fromCheck: failingCheck, status: lost.status)

        await #expect(throws: lost.error) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == Array(Self.keyStrokes.prefix(failingCheck)))
        #expect(harness.pasteboard.contents == .userClipboard)
        if failingCheck > 0 {
            // ⌘A の前にパスへ差し替えているため、書き戻している
            #expect(harness.pasteboard.writes == [.transientText(Self.path), .userClipboard])
        } else {
            #expect(harness.pasteboard.writes.isEmpty)
        }
    }

    @Test("確認が AX の失敗を投げたら、そのまま伝えてキーを送らない")
    func propagatesCheckFailure() async {
        let harness = SequencerHarness()
        harness.targetGuard.checkError = InjectionError.axError(code: Self.axCannotCompleteCode)

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.isEmpty)
    }

    @Test("確認が期限で打ち切られたら、確かめられなかったものとして axError(cannotComplete) を投げる")
    func checkCutOffByDeadlineIsCannotComplete() async {
        let harness = SequencerHarness()
        harness.targetGuard.checkError = ScanCutoff.Reached()

        await #expect(throws: InjectionError.axError(code: Self.axCannotCompleteCode)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.isEmpty)
    }

    @Test("確認が InjectionError 以外で失敗したら axError(failure) にしてキーを送らない")
    func unknownCheckFailureIsAXFailure() async {
        let harness = SequencerHarness()
        harness.targetGuard.checkError = AdapterFailure()

        await #expect(throws: InjectionError.axError(code: -25_200)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes.isEmpty)
    }

    @Test("主方式は注入先を記録しない（記録は PathInjectionFlow が注入の最初に 1 回だけ行う）")
    func doesNotCaptureTarget() async throws {
        let harness = SequencerHarness()

        try await harness.run(path: Self.path)

        #expect(harness.targetGuard.captureCount == 0)
    }
}
