import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: 主方式（⌘⇧G + ペースト）の手順", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let japanesePath = "/Users/me/Documents/資料"

    @Test("待ち時間の既定値は DSN-001 §3.1 のとおり")
    func standardTiming() {
        let timing = PathInjectionTiming.standard

        #expect(timing.sheetWaitLimit == .milliseconds(600))
        #expect(timing.sheetPollInterval == .milliseconds(50))
        #expect(timing.pasteSettleDelay == .milliseconds(100))
        #expect(timing.restoreDelay == .milliseconds(200))
    }

    @Test("⌘⇧G → シート待ち → 退避して書き込み → ⌘A → ⌘V → 100ms → Return → フック → 200ms 後に復元、の順と時刻で進む")
    func runsStepsInOrderWithTiming() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150))

        try await harness.run(path: Self.path)

        let expected: [InjectionEventLog.Entry] = [
            .init(time: .zero, event: .makeProbe),
            .init(time: .zero, event: .prepareForKeyEvents),
            .init(time: .zero, event: .key(.goToFolder)),
            .init(time: .milliseconds(50), event: .sheetCheck(isShown: false)),
            .init(time: .milliseconds(100), event: .sheetCheck(isShown: false)),
            .init(time: .milliseconds(150), event: .sheetCheck(isShown: true)),
            .init(time: .milliseconds(150), event: .pasteboardWrite(.transientText(Self.path))),
            .init(time: .milliseconds(150), event: .key(.selectAll)),
            .init(time: .milliseconds(150), event: .key(.paste)),
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(250), event: .didSubmitGoToSheet(autoConfirm: false)),
            .init(time: .milliseconds(450), event: .pasteboardWrite(.userClipboard)),
        ]
        #expect(harness.log.entries == expected)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("日本語パスもそのまま貼り付ける")
    func pastesJapanesePath() async throws {
        let harness = SequencerHarness()

        try await harness.run(path: Self.japanesePath)

        #expect(harness.pasteboard.writes.first == .transientText(Self.japanesePath))
    }

    @Test("auto_confirm の指定をステップ 8 のフックへ渡す")
    func passesAutoConfirmToHook() async throws {
        let harness = SequencerHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: true)))
    }

    @Test("フックが 200ms 以上かかった場合は、追加で待たずにすぐ復元する（復元は Return 起点）")
    func restoreDelayIsMeasuredFromReturn() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(50))
        harness.hooks.submitDuration = .milliseconds(300)

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(harness.log.entries.last == .init(time: returnTime + .milliseconds(300), event: .pasteboardWrite(.userClipboard)))
    }

    @Test("シートが出なければ 50ms 間隔で 600ms まで確かめ、timeout(waitSheet) を投げる。ペーストボードには触れない")
    func timesOutWaitingForSheet() async {
        let harness = SequencerHarness(sheetAppearsAt: nil)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        let checkTimes = harness.log.entries.filter { $0.event == .sheetCheck(isShown: false) }.map(\.time)
        #expect(checkTimes == (1...12).map { Duration.milliseconds(50 * $0) })
        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("600ms ちょうどの判定でシートが出ていれば続行する")
    func sheetAppearingAtDeadlineIsAccepted() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(600))

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
    }

    @Test("判定（AX の往復）に時間がかかっても、600ms を過ぎた後は再確認せずに打ち切る")
    func stopsCheckingAfterDeadlineEvenIfChecksAreSlow() async {
        let harness = SequencerHarness(sheetAppearsAt: nil)
        harness.sheetDetector.checkLatency = .milliseconds(200)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        // 50ms 後に判定開始 → 250ms に終了 → 50ms 後の 300ms に開始 → … → 550ms 開始・750ms 終了で打ち切り
        let checkTimes = harness.log.entries.filter { $0.event == .sheetCheck(isShown: false) }.map(\.time)
        #expect(checkTimes == [.milliseconds(250), .milliseconds(500), .milliseconds(750)])
    }

    @Test("注入中に他のアプリやユーザーがペーストボードを書き換えたら、その内容を残す")
    func keepsClipboardWrittenByOthersDuringInjection() async throws {
        let harness = SequencerHarness()
        harness.hooks.onSubmit = { harness.pasteboard.simulateExternalWrite(.newerUserCopy) }

        try await harness.run(path: Self.path)

        #expect(harness.pasteboard.contents == .newerUserCopy)
        #expect(harness.pasteboard.writes == [.transientText(Self.path)])
    }

    @Test("続けて注入しても、2 回目の退避に 1 回目のパスが混ざらない")
    func consecutiveRunsPreserveOriginalClipboard() async throws {
        let harness = SequencerHarness()

        try await harness.run(path: Self.path)
        try await harness.run(path: Self.japanesePath)

        #expect(harness.pasteboard.writes == [
            .transientText(Self.path), .userClipboard,
            .transientText(Self.japanesePath), .userClipboard,
        ])
    }
}
