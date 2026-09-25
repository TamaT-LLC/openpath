import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: ⌘A / ⌘V の前に移動先シートの入力欄のフォーカスを待つ（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerFocusTests {
    private static let path = "/Users/me/Library"
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204

    private static func makeHarness(focusArrivesAt focusTime: Duration?) -> SequencerHarness {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), checksBeforeSubmit: true, waitsForFieldFocus: true)
        harness.goToField.focusProvider = { [clock = harness.clock] in
            focusTime.map { clock.elapsed >= $0 } ?? false
        }
        return harness
    }

    @Test("シートが出てもフォーカスが来るまではペーストボードに触れず、来てから差し替えて ⌘A / ⌘V を送る")
    func pastesAfterFocusArrives() async throws {
        let harness = Self.makeHarness(focusArrivesAt: .milliseconds(250))

        try await harness.run(path: Self.path)

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .zero, event: .makeProbe),
            .init(time: .zero, event: .prepareForKeyEvents),
            .init(time: .zero, event: .key(.goToFolder)),
            .init(time: .milliseconds(50), event: .sheetCheck(isShown: false)),
            .init(time: .milliseconds(100), event: .sheetCheck(isShown: false)),
            .init(time: .milliseconds(150), event: .sheetCheck(isShown: true)),
            // 150 / 200ms の確認ではまだフォーカスが無い
            .init(time: .milliseconds(250), event: .pasteboardWrite(.transientText(Self.path))),
            .init(time: .milliseconds(250), event: .key(.selectAll)),
            .init(time: .milliseconds(250), event: .key(.paste)),
            // 貼り付けたパスが入力欄に入ったのを確かめたため、Return の前に戻す
            .init(time: .milliseconds(350), event: .pasteboardWrite(.userClipboard)),
            .init(time: .milliseconds(350), event: .key(.returnKey)),
            .init(time: .milliseconds(350), event: .didSubmitGoToSheet(autoConfirm: false)),
        ]
        #expect(harness.log.entries == expected)
        #expect(harness.goToField.focusReadCount == 3)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("フォーカスを待つときに見つけた入力欄を、確定前の確認でも使う（探し直さない）")
    func reusesFieldFoundWhileWaitingForFocus() async throws {
        let harness = Self.makeHarness(focusArrivesAt: .zero)

        try await harness.run(path: Self.path)

        #expect(harness.goToFieldLocator.lookupCount == 1)
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("250ms 待ってもフォーカスが来なければ、ペーストボードに触れず ⌘A / ⌘V も送らずに timeout(waitPaste) を投げる（副方式へ）")
    func fallsBackWithoutTouchingPasteboardWhenFocusNeverArrives() async {
        let harness = Self.makeHarness(focusArrivesAt: nil)

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.pasteboard.contents == .userClipboard)
        // シートが出た 150ms から、フォーカス待ちの上限の 250ms で打ち切る
        #expect(harness.clock.elapsed == .milliseconds(400))
    }

    @Test("待っている間に入力欄が消えたら（移動先シートが閉じた）、キーを送らずに timeout(waitPaste) を投げる")
    func fallsBackWhenFieldDisappears() async {
        let harness = Self.makeHarness(focusArrivesAt: nil)
        harness.goToField.focusReadError = InjectionError.panelGone

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("入力欄が消えたときにパネルごと閉じていたら、panelGone を投げる")
    func reportsPanelGoneWhenPanelClosesWhileWaiting() async {
        let harness = Self.makeHarness(focusArrivesAt: nil)
        harness.goToField.focusReadError = InjectionError.panelGone
        // ⌘⇧G の前の確認（0 回目）の後、パネルが閉じている
        harness.targetGuard.invalidation = (fromCheck: 1, status: .gone)

        await #expect(throws: InjectionError.panelGone) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("フォーカスを読めなければ確かめられないため、待たずに従来どおり ⌘A / ⌘V を送る")
    func pastesImmediatelyWhenFocusCannotBeRead() async throws {
        let harness = Self.makeHarness(focusArrivesAt: nil)
        harness.goToField.focusReadError = InjectionError.axError(code: Self.axCannotCompleteCode)
        // フォーカスを読めない OS でも、⌘V は入力欄に届くことがある
        harness.keyboard.onPost = { [goToField = harness.goToField, pasteboard = harness.pasteboard] keyStroke in
            guard keyStroke == .paste else { return }
            goToField.simulateTyping(pasteboard.contents.plainText)
        }

        try await harness.run(path: Self.path)

        let pasteTime = try #require(harness.log.entries.first { $0.event == .key(.paste) }?.time)
        #expect(pasteTime == .milliseconds(150))
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("入力欄が見つからなければ確かめられないため、待たずに従来どおり ⌘A / ⌘V を送る")
    func pastesImmediatelyWhenFieldIsNotFound() async throws {
        let harness = Self.makeHarness(focusArrivesAt: nil)
        harness.goToFieldLocator.field = nil

        try await harness.run(path: Self.path)

        let pasteTime = try #require(harness.log.entries.first { $0.event == .key(.paste) }?.time)
        #expect(pasteTime == .milliseconds(150))
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("フォーカスを待っている間にキャンセルされたら、キーを送らずペーストボードにも触れずに CancellationError を投げる")
    func cancelledWhileWaitingForFocus() async {
        let harness = Self.makeHarness(focusArrivesAt: nil)
        harness.goToField.focusProvider = { [clock = harness.clock] in
            if clock.elapsed >= .milliseconds(200) {
                cancelCurrentTask()
            }
            return false
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("フォーカスが来たときに別のアプリへ切り替わっていたら、⌘A を送らずに targetNotFrontmost を投げ、ペーストボードを戻す")
    func stopsWhenTargetChangesWhileWaitingForFocus() async {
        let harness = Self.makeHarness(focusArrivesAt: .milliseconds(200))
        harness.targetGuard.invalidation = (fromCheck: 1, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.contents == .userClipboard)
    }
}
