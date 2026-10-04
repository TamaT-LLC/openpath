import Testing

import OpenPathCore

/// Issue #95: 確定（Return・「移動」の押下）で移動先シートが閉じなければ、主方式の成功とせず副方式へ回し、
/// それでも閉じなければエラーとしてパレットに出す。
@Suite("PathInjectionFlow: 確定した移動先シートが閉じなければ副方式かエラーへ（Issue #95）", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowSheetCloseTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = "/Users/me/Library"
    private static let sheetCloseErrorMessage = "移動できませんでした（「フォルダへ移動」を確定できません）"

    /// 注入の前から移動先シートが開いている状態（macOS 13 以降の移動先シートで「移動」ボタンは無い）。
    private static func makePreopenedHarness() -> FlowHarness {
        let harness = FlowHarness(sheetAppearsAt: nil)
        harness.sheetDetector.isSheetAlreadyShown = true
        harness.goToFieldLocator.goButton = nil
        return harness
    }

    /// 主方式の Return ではシートが閉じず、副方式で送り直した Return で閉じる。
    private static func closeOnSecondReturn(_ harness: FlowHarness) {
        harness.returnClosesSheet = { [keyboard = harness.keyboard] _ in
            keyboard.routedKeyStrokes.filter { $0.keyStroke == .returnKey }.count >= 2
        }
    }

    @Test(
        "開いていたシートが主方式の Return で閉じなければ、副方式で値をセットして Return を送り直し、閉じたら成功とする（auto_confirm なら「開く」まで押す）",
        arguments: [false, true]
    )
    func fallsBackToDirectEntryWhenPreopenedSheetStaysOpen(autoConfirm: Bool) async throws {
        let harness = Self.makePreopenedHarness()
        Self.closeOnSecondReturn(harness)

        try await harness.run(path: Self.path, autoConfirm: autoConfirm)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        let expectedOperations: [InjectionEventLog.Event] = autoConfirm
            ? [.setValue(element: "path", value: Self.path), .press(element: "open")]
            : [.setValue(element: "path", value: Self.path)]
        #expect(harness.elementOperations == expectedOperations)
        #expect(harness.pasteboard.contents == .userClipboard)
        // 主方式: 100ms に Return → 700ms まで閉じない。副方式: 700ms に Return → すぐ閉じ、auto_confirm なら 300ms 後に「開く」
        #expect(harness.clock.elapsed == .milliseconds(autoConfirm ? 1_000 : 700))
        // 副方式の Return の直前に、移動先シートがキーウィンドウかを確かめた
        #expect(harness.targetGuard.goToSheetFocusCheckCount == 1)
    }

    @Test(
        "主方式の Return で閉じなかった後、副方式の Return の直前に移動先シートがキーウィンドウでない（閉じかけ・フォーカスが外れた）か確かめられなければ、Return を送らずにエラーにする（後ろのパネルの「開く」に届かせない）",
        arguments: [false, nil] as [Bool?]
    )
    func doesNotResendReturnWithoutSheetKeyFocus(goToSheetFocus: Bool?) async {
        let harness = Self.makePreopenedHarness()
        harness.returnClosesSheet = { _ in false }
        harness.targetGuard.goToSheetFocus = goToSheetFocus

        let thrown = await #expect(throws: InjectionError.self) {
            try await harness.run(path: Self.path, autoConfirm: true)
        }

        #expect(thrown == .timeout(step: .waitSheetClose))
        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey])
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
        #expect(!harness.log.events.contains(.lookUpOpenButton))
    }

    @Test("送り直す Return の直前の確認は、注入先の確認の後に行い、その後は待たずに Return を送る（注入先の確認の間にシートが閉じても、後ろのパネルへ送らない）")
    func checksSheetKeyFocusLastBeforeReturn() async throws {
        let harness = Self.makePreopenedHarness()
        Self.closeOnSecondReturn(harness)
        harness.targetGuard.logsChecks = true

        try await harness.run(path: Self.path)

        let secondReturnIndex = try #require(harness.log.events.lastIndex(of: .key(.returnKey)))
        #expect(Array(harness.log.events[(secondReturnIndex - 2)...secondReturnIndex]) == [
            .targetCheck,
            .goToSheetFocusCheck,
            .key(.returnKey),
        ])
    }

    @Test("主方式が Return を送る前に失敗した（waitPaste）副方式では、従来どおり移動先シートのキーウィンドウを確かめずに Return を送る")
    func doesNotCheckSheetKeyFocusBeforeFirstReturn() async throws {
        let harness = Self.makePreopenedHarness()
        harness.goToField.hasFocus = false
        harness.targetGuard.goToSheetFocus = false

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.returnKey])
        #expect(harness.targetGuard.goToSheetFocusCheckCount == 0)
    }

    @Test(
        "副方式で確定し直しても閉じなければ、エラー「「フォルダへ移動」を確定できません」にする。auto_confirm でも「開く」は押さない",
        arguments: [false, true]
    )
    func reportsErrorWhenSheetNeverCloses(autoConfirm: Bool) async {
        let harness = Self.makePreopenedHarness()
        harness.returnClosesSheet = { _ in false }

        let thrown = await #expect(throws: InjectionError.self) {
            try await harness.run(path: Self.path, autoConfirm: autoConfirm)
        }

        #expect(thrown == .timeout(step: .waitSheetClose))
        #expect(thrown?.userMessage == Self.sheetCloseErrorMessage)
        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey, .returnKey])
        #expect(!harness.log.events.contains(.lookUpOpenButton))
        #expect(harness.pasteboard.contents == .userClipboard)
        // 主方式: 100ms に Return → 700ms で諦める。副方式: 700ms に Return → 1,300ms で諦める
        #expect(harness.clock.elapsed == .milliseconds(1_300))
    }

    @Test("副方式で確定し直した後に移動先シートを探せず（AX の失敗）、閉じたことを確かめられなければ、成功にせずエラーにする。「開く」は押さない")
    func reportsErrorWhenSecondaryCannotConfirmClose() async {
        let harness = Self.makePreopenedHarness()
        harness.returnClosesSheet = { _ in false }
        // 副方式の Return の後は、移動先シートを探せない
        harness.submitCheckLocator.errorProvider = { [keyboard = harness.keyboard] in
            let returnCount = keyboard.routedKeyStrokes.filter { $0.keyStroke == .returnKey }.count
            return returnCount >= 2 ? InjectionError.axError(code: -25_204) : nil
        }

        let thrown = await #expect(throws: InjectionError.self) {
            try await harness.run(path: Self.path, autoConfirm: true)
        }

        #expect(thrown == .timeout(step: .waitSheetClose))
        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey, .returnKey])
        #expect(!harness.log.events.contains(.lookUpOpenButton))
    }

    @Test("注入先のプロセスへ送った Return でシートが閉じなければ、副方式の Return はシステム経由で送り直す")
    func secondaryReturnUsesSystemRouteAfterTargetProcessReturnFails() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150), fallsBackWhenSheetMissing: true)
        harness.goToFieldLocator.goButton = nil
        harness.returnClosesSheet = { $0 == .systemWide }

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(harness.elementOperations == [.setValue(element: "path", value: Self.path)])
    }

    @Test("「移動」ボタンのある移動先シートでは、Return で閉じなければ副方式で「移動」を押して確定し直す")
    func secondaryPressesGoButtonWhenReturnDoesNotClose() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150))
        harness.returnClosesSheet = { _ in false }

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste, .returnKey])
        #expect(harness.elementOperations == [
            .setValue(element: "path", value: Self.path),
            .press(element: "go"),
            .press(element: "open"),
        ])
    }

    @Test("主方式が諦めた直後に入力欄が見つからなくなっても、閉じたとは言い切れないため成功にしない。確定し直さず（後ろのパネルへ Return を送らない）、「開く」も押さない")
    func doesNotSucceedWhenFieldVanishesAfterPrimaryGaveUp() async {
        let harness = Self.makePreopenedHarness()
        // 主方式の Return から 610ms で閉じる。主方式は 600ms（注入の開始から 700ms）の確認で諦め、
        // 副方式が探す走査（10ms）の間に閉じる
        harness.sheetCloseDelay = .milliseconds(610)
        harness.goToFieldLocator.lookupLatency = .milliseconds(10)

        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: Self.path, autoConfirm: true)
        }

        #expect(harness.log.keyStrokes == [.selectAll, .paste, .returnKey])
        #expect(harness.elementOperations.isEmpty)
        #expect(!harness.log.events.contains(.lookUpOpenButton))
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("QA の /tmp の試行と同じく候補の選択が追いつかないまま確定し、主方式の Return でシートが閉じなくても、副方式で「開く」まで 2.5 秒の全体タイムアウトに収まる")
    func preopenedFallbackWithSlowSuggestionFitsOverallTimeout() async throws {
        let harness = Self.makePreopenedHarness()
        let suggestions = SuggestionListFake()
        suggestions.selectedPathProvider = { "/Users/me/前回の場所" }
        harness.submitCheckLocator.suggestionList = suggestions
        harness.goToFieldLocator.suggestionList = suggestions
        Self.closeOnSecondReturn(harness)
        // macOS 27 で、Return から「開く」が押せる状態になる（シートが閉じる）まで約 410ms（Issue #89）
        harness.sheetCloseDelay = .milliseconds(400)

        try await harness.run(path: Self.path, autoConfirm: true)

        let tail = harness.log.entries.drop { $0.event != .key(.returnKey) }
        #expect(Array(tail) == [
            // 主方式: 確定前の確認で 250ms 待ってから Return。600ms 待っても閉じない
            .init(time: .milliseconds(350), event: .key(.returnKey)),
            // 副方式: 値をセットし、確定前の確認で 250ms 待ってから Return
            .init(time: .milliseconds(950), event: .lookUpGoToField),
            .init(time: .milliseconds(950), event: .setValue(element: "path", value: Self.path)),
            .init(time: .milliseconds(1_200), event: .prepareForKeyEvents),
            .init(time: .milliseconds(1_200), event: .key(.returnKey)),
            // 400ms 後に閉じたのを確かめる。「開く」の待機（確定から 300ms）は過ぎているため、待たずに押す
            .init(time: .milliseconds(1_600), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(1_600), event: .lookUpOpenButton),
            .init(time: .milliseconds(1_600), event: .press(element: "open")),
        ])
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
    }

    @Test("初回の ③ で約 900ms に出たシートで、主方式・副方式のどちらの確定でも閉じなくても、エラーは 2.5 秒の全体タイムアウトの前に出る")
    func slowSheetThatNeverClosesFailsWithinOverallTimeout() async {
        let harness = SlowSheetInjection.primary.makeHarness()
        harness.returnClosesSheet = { _ in false }

        await #expect(throws: InjectionError.timeout(step: .waitSheetClose)) {
            try await harness.run(path: SlowSheetInjection.path, autoConfirm: true)
        }

        // 主方式: 1,250ms に Return → 1,850ms で諦める。副方式: 1,850ms に Return → 2,450ms で諦める
        #expect(harness.clock.elapsed == .milliseconds(2_450))
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
        #expect(!harness.log.events.contains(.lookUpOpenButton))
    }

    @Test("シートが Return から 400ms で閉じる場合、auto_confirm の「開く」は閉じた直後に押す（確定から 300ms の待機を重ねない）")
    func autoConfirmDoesNotAddDelayAfterSheetCloses() async throws {
        let harness = FlowHarness(sheetAppearsAt: .milliseconds(150))
        harness.sheetCloseDelay = .milliseconds(400)

        try await harness.run(path: Self.path, autoConfirm: true)

        let tail = harness.log.entries.drop { $0.event != .key(.returnKey) }
        #expect(Array(tail) == [
            .init(time: .milliseconds(250), event: .key(.returnKey)),
            .init(time: .milliseconds(650), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(650), event: .lookUpOpenButton),
            .init(time: .milliseconds(650), event: .press(element: "open")),
        ])
    }
}
