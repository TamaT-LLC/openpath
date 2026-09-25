import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: 貼り付けを確かめたら Return の前にペーストボードを戻す（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerEarlyRestoreTests {
    private static let path = "/Users/me/Library"

    /// 入力欄のフォーカスを待ち、確定前の確認もする（PanelInjector と同じ組み合わせ）。
    private static func makeHarness() -> SequencerHarness {
        SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true, waitsForFieldFocus: true)
    }

    @Test("貼り付けで入力欄が前回の値から移動先に変わったのを確かめたら、Return の前にペーストボードを戻し、Return の後は待たない")
    func restoresBeforeReturnWhenPasteIsConfirmed() async throws {
        let harness = Self.makeHarness()

        try await harness.run(path: Self.path)

        let tail = harness.log.entries.drop { $0.event != .key(.paste) }
        #expect(Array(tail) == [
            .init(time: .milliseconds(150), event: .key(.paste)),
            .init(time: .milliseconds(250), event: .pasteboardWrite(.userClipboard)),
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(250), event: .didSubmitGoToSheet(autoConfirm: false)),
        ])
        #expect(harness.clock.elapsed == .milliseconds(250))
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("候補リストが追いつかなくても（suggestionNotUpdated）、入力欄が移動先に変わっていれば Return の前に戻す")
    func restoresBeforeReturnWhenOnlySuggestionLags() async throws {
        let harness = Self.makeHarness()
        harness.suggestions.selectedPathProvider = { SequencerHarness.previousGoToPath }

        try await harness.run(path: Self.path)

        let restoreIndex = try #require(harness.log.events.firstIndex(of: .pasteboardWrite(.userClipboard)))
        let returnIndex = try #require(harness.log.events.firstIndex(of: .key(.returnKey)))
        #expect(restoreIndex < returnIndex)
        #expect(harness.clock.elapsed == .milliseconds(500))
    }

    @Test("入力欄に最初から移動先が入っていたら（前回と同じ移動先）、⌘V が処理されたか分からないため従来どおり Return の 200ms 後に戻す")
    func keepsRestoreDelayWhenFieldAlreadyHeldPath() async throws {
        let harness = Self.makeHarness()
        harness.goToField.simulateTyping(Self.path)

        try await harness.run(path: Self.path)

        let tail = harness.log.entries.drop { $0.event != .key(.returnKey) }
        #expect(Array(tail) == [
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(250), event: .didSubmitGoToSheet(autoConfirm: false)),
            .init(time: .milliseconds(450), event: .pasteboardWrite(.userClipboard)),
        ])
    }

    @Test("貼り付けの前に入力欄の値を読めなければ、従来どおり Return の 200ms 後に戻す")
    func keepsRestoreDelayWhenValueBeforePasteIsUnknown() async throws {
        let harness = Self.makeHarness()
        harness.goToField.valueReadError = InjectionError.axError(code: -25_204)
        let simulatePaste = harness.keyboard.onPost
        harness.keyboard.onPost = { [goToField = harness.goToField] keyStroke in
            // 貼り付けの前（⌘A の前）の読み取りだけ失敗させ、確定前の確認では読めるようにする
            if keyStroke == .selectAll {
                goToField.valueReadError = nil
            }
            simulatePaste?(keyStroke)
        }

        try await harness.run(path: Self.path)

        #expect(harness.log.entries.last == .init(time: .milliseconds(450), event: .pasteboardWrite(.userClipboard)))
    }

    @Test("フォーカスを待たない（入力欄を見つけていない）ときは、従来どおり Return の 200ms 後に戻す")
    func keepsRestoreDelayWithoutFieldFocusWait() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)

        try await harness.run(path: Self.path)

        #expect(harness.log.entries.last == .init(time: .milliseconds(450), event: .pasteboardWrite(.userClipboard)))
    }

    @Test("auto_confirm でも Return の前に戻し、「開く」を押し終えたら待たずに終わる")
    func restoresBeforeReturnWithAutoConfirm() async throws {
        let harness = Self.makeHarness()
        harness.hooks.submitDuration = .milliseconds(300)

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.pasteboard.writes == [.transientText(Self.path), .userClipboard])
        let restoreIndex = try #require(harness.log.events.firstIndex(of: .pasteboardWrite(.userClipboard)))
        let submitIndex = try #require(harness.log.events.firstIndex(of: .didSubmitGoToSheet(autoConfirm: true)))
        #expect(restoreIndex < submitIndex)
        #expect(harness.clock.elapsed == .milliseconds(550))
    }

    @Test("Return の前に戻せなかったときも Return は送って移動させ、最後に pasteboardRestoreFailed を投げる")
    func reportsEarlyRestoreFailureAfterSubmitting() async {
        let harness = Self.makeHarness()
        harness.pasteboard.onWrite = { [unowned pasteboard = harness.pasteboard, log = harness.log] snapshot in
            log.record(.pasteboardWrite(snapshot))
            // パスの書き込みは成功させ、元の内容への書き戻しを失敗させる
            pasteboard.remainingWriteFailures = 1
        }

        await #expect(throws: InjectionError.pasteboardRestoreFailed) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
        #expect(harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
        // 書き戻しは 1 回だけ試す
        #expect(harness.pasteboard.writes == [.transientText(Self.path)])
    }

    @Test("Return の前に戻した後で Return を送れなくなっても（注入先が最前面でない）、二度は書き戻さない")
    func doesNotRestoreTwiceWhenReturnIsNotSent() async {
        let harness = Self.makeHarness()
        // 0: ⌘⇧G、1: ⌘A、2: ⌘V、3: Return の前の確認
        harness.targetGuard.invalidation = (fromCheck: 3, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste])
        #expect(harness.pasteboard.writes == [.transientText(Self.path), .userClipboard])
        #expect(harness.pasteboard.contents == .userClipboard)
    }
}
