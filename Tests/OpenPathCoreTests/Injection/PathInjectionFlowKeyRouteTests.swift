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

    @Test("主方式が ③（システム経由の ⌘⇧G）でもシートを開けなければ、副方式の Return はシステム経由で送る")
    func secondaryUsesSystemRouteWhenEveryStageFails() async throws {
        let harness = Self.makeHarness(sheetAppearsAt: nil)
        harness.focusReader.element = .other
        // 主方式の基準比較ではシートを拾えないが、副方式は入力欄を見つけて値をセットする

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .goToFolder, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("① が届かず ③ で開いた移動先シートでも（② の / を経る最も遅い経路）、auto_confirm の「開く」まで 1.5 秒の全体タイムアウトに収まる")
    func systemGoToWithAutoConfirmFitsOverallTimeout() async throws {
        let harness = FlowHarness(sheetAppearsAt: nil, fallsBackWhenSheetMissing: true)
        harness.keyboard.onRoutedPost = { [harness] keyStroke, route in
            guard keyStroke == .goToFolder, route == .systemWide else { return }
            harness.sheetDetector.appearsAt = harness.clock.elapsed + .milliseconds(150)
        }

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.log.keyStrokes == [.goToFolder, .slash, .goToFolder, .selectAll, .paste, .returnKey])
        #expect(harness.log.events.contains(.press(element: "open")))
        #expect(!harness.log.events.contains(.lookUpGoToField))
        // ③ を 400ms に送り、550ms に出たシートへ貼り付け、650ms の Return から 300ms 後に「開く」を押す
        #expect(harness.clock.elapsed == .milliseconds(950))
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
    }

    @Test("注入先のプロセスへの ⌘⇧G で ① の期限（200ms）より後に出たシートも、続く段の待ちで拾って主方式で移動する")
    func picksUpLateSheetFromTargetProcessRoute() async throws {
        // QA（macOS 26.6.2）で、移動先シートが ⌘⇧G から 400ms で AX に現れた条件
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(400), fallsBackWhenSheetMissing: true)
        harness.focusReader.element = .other

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .goToFolder, .selectAll, .paste, .returnKey])
        #expect(!harness.log.events.contains(.lookUpGoToField))
        #expect(harness.goToField.currentValue == Self.path)
    }
}
