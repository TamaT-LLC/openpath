import Testing

import OpenPathCore

/// Issue #95 の実機 QA（macOS 26.6.2 の VS Code）で、先に開いた移動先シートへ貼り付けて Return を送ったが、
/// シートが残って移動していないのに `主方式で注入しました` になった。Return を送っただけでは成功とせず、
/// シートが閉じたのを確かめてから成功とする。
@Suite("GoToFolderPasteSequencer: 移動先シートが閉じたのを確かめてから成功とする（Issue #95）", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerSheetCloseTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = "/Users/me/Library"

    /// 注入の前から移動先シートが開いている状態（QA の VS Code の再現手順）。
    private static func makePreopenedHarness() -> SequencerHarness {
        let harness = SequencerHarness(
            sheetAppearsAt: nil,
            checksBeforeSubmit: true,
            waitsForFieldFocus: true,
            fallsBackWhenSheetMissing: true
        )
        harness.sheetDetector.isSheetAlreadyShown = true
        return harness
    }

    private static func didSubmit(_ harness: SequencerHarness) -> Bool {
        harness.log.events.contains { event in
            if case .didSubmitGoToSheet = event { return true }
            return false
        }
    }

    @Test(
        "開いていたシートに Return を送ってもシートが閉じなければ、成功にせず timeout(waitSheetClose) を投げる（副方式へ）。auto_confirm の差し込み口は呼ばず、ペーストボードは戻す",
        arguments: [false, true]
    )
    func preopenedSheetThatStaysOpenIsNotSuccess(autoConfirm: Bool) async {
        let harness = Self.makePreopenedHarness()
        harness.returnClosesSheet = { _ in false }

        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path, autoConfirm: autoConfirm)
        }

        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey])
        #expect(!Self.didSubmit(harness))
        #expect(harness.pasteboard.contents == .userClipboard)
        // 貼り付けの 100ms 後に Return を送り、そこから 600ms 待って閉じなければ諦める
        #expect(harness.clock.elapsed == .milliseconds(700))
    }

    @Test(
        "開いていたシートは、閉じたのを確かめてから成功とする。auto_confirm の差し込み口には、閉じるのを待った時間を渡す",
        arguments: [false, true]
    )
    func succeedsOnlyAfterPreopenedSheetCloses(autoConfirm: Bool) async throws {
        let harness = Self.makePreopenedHarness()
        harness.sheetCloseDelay = .milliseconds(200)

        try await harness.run(path: Self.path, autoConfirm: autoConfirm)

        let tail = harness.log.entries.drop { $0.event != .key(.returnKey) }
        #expect(Array(tail) == [
            .init(time: .milliseconds(100), event: .key(.returnKey)),
            // Return の 200ms 後にシートが閉じたのを確かめてから呼ぶ
            .init(time: .milliseconds(300), event: .didSubmitGoToSheet(autoConfirm: autoConfirm)),
        ])
        #expect(harness.hooks.elapsedSinceSubmit == [.milliseconds(200)])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("開いていたシートでは、⌘A / ⌘V は注入先のプロセスへ、確定の Return はシステム経由で送る（注入先のプロセスへ送った Return はリモートのパネルに届かないことがある）")
    func sendsReturnThroughSystemRouteForPreopenedSheet() async throws {
        let harness = Self.makePreopenedHarness()
        // QA の VS Code: 注入先のプロセスへ送った Return ではシートが閉じない
        harness.returnClosesSheet = { $0 == .systemWide }

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        #expect(Self.didSubmit(harness))
    }

    @Test("注入先のプロセスへの ⌘⇧G で開いたシートは、従来どおり Return も注入先のプロセスへ送る。それで閉じなければ timeout(waitSheetClose) を投げ、副方式の Return はシステム経由に切り替える")
    func switchesRouteWhenTargetProcessReturnDoesNotClose() async {
        let harness = SequencerHarness(
            sheetAppearsAt: .milliseconds(150),
            checksBeforeSubmit: true,
            waitsForFieldFocus: true,
            fallsBackWhenSheetMissing: true
        )
        harness.returnClosesSheet = { $0 == .systemWide }

        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .targetProcess),
        ])
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("候補の選択が追いつかないまま（suggestionNotUpdated）確定しても、閉じなければ成功にしない（QA の /tmp の試行）")
    func suggestionNotUpdatedStillRequiresSheetToClose() async {
        let harness = Self.makePreopenedHarness()
        harness.suggestions.selectedPathProvider = { SequencerHarness.previousGoToPath }
        harness.returnClosesSheet = { _ in false }

        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path)
        }

        // 確定前の確認は 250ms 待って suggestionNotUpdated のまま Return を送る（従来どおり）
        let returnEntry = harness.log.entries.first { $0.event == .key(.returnKey) }
        #expect(returnEntry?.time == .milliseconds(350))
    }

    @Test("閉じたかを確かめられない（入力欄を見つけていない）構成では、従来どおり Return を送ったら成功とする")
    func succeedsWithoutVerificationWhenFieldIsUnknown() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150))
        harness.returnClosesSheet = { _ in false }

        try await harness.run(path: Self.path)

        #expect(Self.didSubmit(harness))
    }

    @Test("シートが閉じるのを待っている間にキャンセルされたら、CancellationError を投げてペーストボードを戻す")
    func cancelledWhileWaitingForSheetToClose() async {
        let harness = Self.makePreopenedHarness()
        harness.returnClosesSheet = { _ in false }
        let suspension = Suspension()
        harness.keyboard.onRoutedPost = { [locator = harness.goToFieldLocator] keyStroke, _ in
            guard keyStroke == .returnKey else { return }
            locator.suspension = suspension
        }
        let task = harness.startRun(path: Self.path)

        await suspension.waitUntilSuspended()
        task.cancel()
        suspension.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!Self.didSubmit(harness))
        #expect(harness.pasteboard.contents == .userClipboard)
    }
}
