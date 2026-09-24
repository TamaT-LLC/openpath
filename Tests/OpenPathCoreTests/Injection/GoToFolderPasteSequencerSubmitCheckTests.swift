import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: Return の前の移動先シートの確認（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerSubmitCheckTests {
    private static let path = "/Users/me/Library"

    @Test("貼り付けたパスが入力欄に入り候補の選択も移動先なら、従来どおり ⌘V の 100ms 後に Return を送る")
    func submitsWithoutExtraWaitWhenReady() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        harness.suggestions.selectedPathProvider = { Self.path }

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(250))
        #expect(harness.goToField.valueReadCount == 1)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("候補リストが前回の移動先を選んだままなら、移動先に追いつくのを待ってから Return を送る")
    func waitsForSuggestionListToCatchUp() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        // macOS 27 では、貼り付けから候補リストの出し直しまで 200〜300ms かかった
        harness.suggestions.selectedPathProvider = { [clock = harness.clock] in
            clock.elapsed >= .milliseconds(150 + 250) ? Self.path : SequencerHarness.previousGoToPath
        }

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(400))
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("候補リストが期限（確認を始めてから 250ms）までに追いつかなくても、入力欄が移動先なら Return を送る")
    func submitsWhenSuggestionListNeverCatchesUp() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        harness.suggestions.selectedPathProvider = { SequencerHarness.previousGoToPath }

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(500))
    }

    @Test("貼り付けが効かず入力欄に前回の移動先が残っていたら、Return を送らずに timeout(waitPaste) を投げ、ペーストボードを戻す")
    func doesNotSubmitPreviousPathWhenPasteIsNotApplied() async {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        // ⌘V が入力欄に届かない（入力欄は前回の移動先のまま）
        harness.keyboard.onPost = nil

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste])
        #expect(!harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
        #expect(harness.pasteboard.contents == .userClipboard)
        // 失敗時は 200ms を待たずにすぐ戻す
        #expect(harness.log.entries.last == .init(time: .milliseconds(500), event: .pasteboardWrite(.userClipboard)))
    }

    @Test("⌘A が効かずに前回の値へ追記されたときも、Return を送らない")
    func doesNotSubmitAppendedValue() async {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        harness.keyboard.onPost = { [goToField = harness.goToField] keyStroke in
            guard keyStroke == .paste else { return }
            goToField.simulateTyping(SequencerHarness.previousGoToPath + Self.path)
        }

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(!harness.log.keyStrokes.contains(.returnKey))
    }

    @Test("移動先シートの入力欄を AX で読めなければ、確かめずに従来どおり Return を送る")
    func submitsWhenSheetCannotBeRead() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        harness.goToFieldLocator.field = nil

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(250))
    }

    @Test("確認している間にキャンセルされたら、Return を送らずに CancellationError を投げ、ペーストボードを戻す")
    func cancelledWhileChecking() async {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true)
        harness.suggestions.selectedPathProvider = {
            cancelCurrentTask()
            return SequencerHarness.previousGoToPath
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run(path: Self.path)
        }

        #expect(!harness.log.keyStrokes.contains(.returnKey))
        #expect(harness.pasteboard.contents == .userClipboard)
    }
}
