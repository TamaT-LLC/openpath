import Testing

import OpenPathCore

@Suite("PathInjectionFlow: 副方式の Return は、主方式が最後に使ったキーの経路で送る", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowKeyRouteTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = "/Users/me/Library"

    /// 入力欄にフォーカスが来ず、主方式は貼り付けずに副方式へ回る。副方式は値をセットし、AX でフォーカスを与えてから Return を送る。
    private static func makeHarness(sheetAppearsAt: Duration?) -> FlowHarness {
        let harness = FlowHarness(sheetAppearsAt: sheetAppearsAt, fallsBackWhenSheetMissing: true)
        harness.goToField.hasFocus = false
        harness.goToFieldLocator.goButton = nil
        return harness
    }

    @Test("主方式が注入先のプロセスへの ⌘⇧G でシートを開いたなら、副方式の Return も注入先のプロセスへ送る")
    func secondaryUsesTargetProcessRoute() async throws {
        let harness = Self.makeHarness(sheetAppearsAt: .milliseconds(150))

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .targetProcess),
        ])
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
    }

    @Test("主方式が代替（システム経由の /）でシートを開いたなら、副方式の Return もシステム経由で送る")
    func secondaryUsesSystemRouteAfterFallback() async throws {
        let harness = Self.makeHarness(sheetAppearsAt: nil)
        harness.keyboard.onRoutedPost = { [harness] keyStroke, route in
            guard keyStroke == .slash, route == .systemWide else { return }
            harness.sheetDetector.appearsAt = harness.clock.elapsed + .milliseconds(150)
        }

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .slash, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("通常の注入（主方式で成功）では、すべてのキーを注入先のプロセスへ送り、フォーカスは読まない")
    func primarySuccessUsesTargetProcessOnly() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150), fallsBackWhenSheetMissing: true)

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.keyboard.routedKeyStrokes.allSatisfy { $0.route == .targetProcess })
        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
        #expect(harness.focusReader.readTimes.isEmpty)
        #expect(harness.log.events.contains(.press(element: "open")))
    }
}
