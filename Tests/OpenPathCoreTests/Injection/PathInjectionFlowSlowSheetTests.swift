import Testing

import OpenPathCore

/// Issue #29 の実機 QA（macOS 26 の VS Code）で、初回の注入は移動先シートが ③（システム経由の ⌘⇧G）で +887ms に開いたが、
/// その後のペーストと確定が 1.5 秒の全体タイムアウトに間に合わなかった。条件は `SlowSheetInjection` を参照。
/// 各段の待ち（200 / 300 / 500ms）は変えずに、こうした遅いが成功する注入が全体タイムアウトの内に終わることを確かめる。
@Suite("PathInjectionFlow: 初回の ③ で移動先シートが遅れて出る注入（Issue #29）", .timeLimit(.minutes(1)))
@MainActor
struct PathInjectionFlowSlowSheetTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = SlowSheetInjection.path
    /// ② 以降は、シートが出た ③ の経路（システム経由）で送る。
    private static let keyStrokesUntilSheet = [
        Routed(keyStroke: .goToFolder, route: .targetProcess),
        Routed(keyStroke: .slash, route: .systemWide),
        Routed(keyStroke: .goToFolder, route: .systemWide),
    ]

    @Test("③ の移動先シートは、③ の最後の確認（900ms）で見つける", arguments: SlowSheetInjection.allCases)
    func findsSheetAtLastCheckOfSystemGoTo(_ injection: SlowSheetInjection) async throws {
        let harness = injection.makeHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        let firstShown = harness.log.entries.first { $0.event == .sheetCheck(isShown: true) }
        #expect(firstShown?.time == .milliseconds(900))
        #expect(Array(harness.keyboard.routedKeyStrokes.prefix(Self.keyStrokesUntilSheet.count)) == Self.keyStrokesUntilSheet)
    }

    @Test("主方式で貼り付けて「開く」まで押すと 1.5 秒を超えるが、全体タイムアウトの内に終わる")
    func primaryWithAutoConfirmFitsOverallTimeout() async throws {
        let harness = SlowSheetInjection.primary.makeHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.keyboard.routedKeyStrokes == Self.keyStrokesUntilSheet + [
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(!harness.log.events.contains(.lookUpGoToField))
        let tail = harness.log.entries.drop { $0.event != .key(.paste) }
        #expect(Array(tail) == [
            // 入力欄にフォーカスが来た 1,000ms に貼り付け、候補リストが追いついた 1,250ms に戻して確定し、300ms 後に「開く」を押す
            .init(time: .milliseconds(1_000), event: .key(.paste)),
            .init(time: .milliseconds(1_250), event: .pasteboardWrite(.userClipboard)),
            .init(time: .milliseconds(1_250), event: .key(.returnKey)),
            .init(time: .milliseconds(1_250), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(1_550), event: .lookUpOpenButton),
            .init(time: .milliseconds(1_550), event: .press(element: "open")),
        ])
        #expect(harness.goToField.currentValue == Self.path)
        #expect(harness.pasteboard.contents == .userClipboard)
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
    }

    @Test("⌘V が入力欄に届かず副方式で値をセットして「開く」まで押すと 1.5 秒を超えるが、全体タイムアウトの内に終わる")
    func secondaryWithAutoConfirmFitsOverallTimeout() async throws {
        let harness = SlowSheetInjection.secondaryAfterFieldMismatch.makeHarness()

        try await harness.run(path: Self.path, autoConfirm: true)

        #expect(harness.keyboard.routedKeyStrokes == Self.keyStrokesUntilSheet + [
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        let tail = harness.log.entries.drop { $0.event != .lookUpGoToField }
        #expect(Array(tail) == [
            // 主方式は貼り付けの 100ms 後から確定前の確認を 250ms 続けて fieldMismatch で諦め、
            // 副方式は値をセットして Return を送り、300ms 後に「開く」を押す
            .init(time: .milliseconds(1_350), event: .lookUpGoToField),
            .init(time: .milliseconds(1_350), event: .setValue(element: "path", value: Self.path)),
            .init(time: .milliseconds(1_350), event: .prepareForKeyEvents),
            .init(time: .milliseconds(1_350), event: .key(.returnKey)),
            .init(time: .milliseconds(1_350), event: .didSubmitGoToSheet(autoConfirm: true)),
            .init(time: .milliseconds(1_650), event: .lookUpOpenButton),
            .init(time: .milliseconds(1_650), event: .press(element: "open")),
        ])
        #expect(harness.goToField.currentValue == Self.path)
        #expect(harness.pasteboard.contents == .userClipboard)
        #expect(harness.clock.elapsed < AppCoordinator.injectionTimeout)
    }
}
