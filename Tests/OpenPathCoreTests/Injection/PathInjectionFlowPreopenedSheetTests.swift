import Testing

import OpenPathCore

@Suite("PathInjectionFlow: 先に開いた「フォルダへ移動」シートへの注入（Issue #95）", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowPreopenedSheetTests {
    private static let path = "/Users/me/Library"

    /// ⌘⇧G で開いた移動先シートが既にある状態（macOS 13 以降の移動先シートで「移動」ボタンは無い）。
    /// ⌘⇧G を送っても新しいシートは出ない（macOS 27 で確認）。
    private static func makeHarness() -> FlowHarness {
        let harness = FlowHarness(sheetAppearsAt: nil)
        harness.sheetDetector.isSheetAlreadyShown = true
        harness.goToFieldLocator.goButton = nil
        return harness
    }

    @Test("⌘⇧G を送らずに開いているシートの入力欄へ貼り付けて移動し、auto_confirm なら「開く」も押す")
    func injectsIntoPreopenedSheetWithAutoConfirm() async throws {
        let harness = Self.makeHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey])
        #expect(harness.log.events.contains(.press(element: "open")))
        #expect(!harness.log.events.contains(.lookUpGoToField))
        #expect(harness.pasteboard.contents == .userClipboard)
        // 貼り付け 0ms → 確定前の確認 100ms → Return → 300ms 待って「開く」
        #expect(harness.clock.elapsed == .milliseconds(400))
    }

    @Test("開いているシートの入力欄にキーが届かなければ、⌘⇧G を送らないまま副方式で同じ入力欄に値をセットして確定する")
    func fallsBackToDirectEntryIntoPreopenedSheet() async throws {
        let harness = Self.makeHarness()
        harness.goToField.hasFocus = false

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.returnKey])
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
        #expect(harness.log.events.contains(.focusField(element: "path")))
        #expect(harness.pasteboard.writes.isEmpty)
    }
}
