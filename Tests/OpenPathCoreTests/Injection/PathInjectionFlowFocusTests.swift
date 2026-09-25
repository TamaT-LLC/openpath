import Testing

import OpenPathCore

@Suite("PathInjectionFlow: 移動先シートの入力欄のフォーカスを待ってからキーを送る（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowFocusTests {
    private static let path = "/Users/me/Library"
    /// ⌘⇧G で開いた移動先シートの入力欄に、最初から入っている前回の移動先。
    private static let previousPath = "/Users/me/前回の場所"

    /// QA（macOS 26.6.2）の debug ログに近い条件: 移動先シートが 400ms で AX に現れ、入力欄はその 100ms 後にフォーカスを持つ。
    /// 移動先シートの候補リストは、入力欄が変わってから 250ms 遅れて移動先の候補を選ぶ（macOS 27 で 200〜300ms）。
    private static func makeQAConditionHarness() -> FlowHarness {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(400))
        let clock = harness.clock
        harness.goToField.simulateTyping(previousPath)
        harness.goToField.focusProvider = { clock.elapsed >= .milliseconds(500) }
        let suggestions = SuggestionListFake()
        suggestions.selectedPathProvider = { clock.elapsed >= .milliseconds(500 + 250) ? path : previousPath }
        harness.submitCheckLocator.suggestionList = suggestions
        harness.goToFieldLocator.suggestionList = suggestions
        return harness
    }

    @Test("QA の条件でも主方式で移動し、副方式に落ちない。貼り付けを確かめたペーストボードは Return の前に戻し、1 秒未満で終わる")
    func primarySucceedsUnderQACondition() async throws {
        let harness = Self.makeQAConditionHarness()

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
        #expect(!harness.log.events.contains(.lookUpGoToField))
        #expect(harness.elementOperations.isEmpty)
        let tail = harness.log.entries.drop { $0.event != .key(.paste) }
        #expect(Array(tail) == [
            // フォーカスが来た 500ms に貼り付け、候補リストが追いついた 750ms に戻して確定する
            .init(time: .milliseconds(500), event: .key(.paste)),
            .init(time: .milliseconds(750), event: .pasteboardWrite(.userClipboard)),
            .init(time: .milliseconds(750), event: .key(.returnKey)),
            .init(time: .milliseconds(750), event: .didSubmitGoToSheet(autoConfirm: false)),
        ])
        #expect(harness.pasteboard.contents == .userClipboard)
        #expect(harness.clock.elapsed < .milliseconds(1000))
    }

    @Test("QA の条件で auto_confirm でも、「開く」を押して 1.5 秒の全体タイムアウトに 400ms 以上の余裕を残して終わる")
    func primaryWithAutoConfirmFitsTimeoutUnderQACondition() async throws {
        let harness = Self.makeQAConditionHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.log.events.contains(.press(element: "open")))
        #expect(!harness.log.events.contains(.lookUpGoToField))
        #expect(harness.clock.elapsed == .milliseconds(1050))
        #expect(AppCoordinator.injectionTimeout - harness.clock.elapsed >= .milliseconds(400))
    }

    @Test("入力欄にフォーカスが来なければ、ペーストボードに触れずに副方式で値をセットし、AX でフォーカスを与えてから Return で確定する")
    func fallsBackToDirectEntryWhenFocusNeverArrives() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150))
        harness.goToField.hasFocus = false
        harness.goToFieldLocator.goButton = nil

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .returnKey])
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
        let tail = harness.log.entries.drop { $0.event != .lookUpGoToField }
        let expected: [InjectionEventLog.Entry] = [
            // 主方式はシートが出た 150ms からフォーカスを 250ms 待って諦める
            .init(time: .milliseconds(400), event: .lookUpGoToField),
            .init(time: .milliseconds(400), event: .setValue(element: "path", value: Self.path)),
            .init(time: .milliseconds(400), event: .prepareForKeyEvents),
            // 副方式も Return の前にフォーカスを 250ms 待ち、来なければ AX で与える
            .init(time: .milliseconds(650), event: .focusField(element: "path")),
            .init(time: .milliseconds(650), event: .key(.returnKey)),
            .init(time: .milliseconds(650), event: .didSubmitGoToSheet(autoConfirm: false)),
        ]
        #expect(Array(tail) == expected)
    }

    @Test("主方式がフォーカスを諦めた後に来たフォーカスは、副方式が拾って Return を送る")
    func directEntryPicksUpLateFocus() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150))
        harness.goToField.focusProvider = { [clock = harness.clock] in clock.elapsed >= .milliseconds(450) }
        harness.goToFieldLocator.goButton = nil

        try await harness.run(path: Self.path)

        let returnTime = try #require(harness.log.entries.first { $0.event == .key(.returnKey) }?.time)
        #expect(returnTime == .milliseconds(450))
        #expect(!harness.log.events.contains(.focusField(element: "path")))
    }
}
