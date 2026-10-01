import Testing

import OpenPathCore

@Suite("GoToFolderPasteSequencer: キーを注入先のプロセスへ送り、シートが出なければ代替で送り直す", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerKeyRouteTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = "/Users/me/Library"
    /// 代替のキーを送ってから移動先シートが出るまでの時間。
    private static let fallbackSheetLatency: Duration = .milliseconds(150)

    /// 注入先のプロセスへ送ったキーは届かず、システム経由で送ったキーだけが届く状況（シートは出ない状態から始める）。
    /// `opensSheet` の経路・キーで送ったら、その 150ms 後に移動先シートが出る。
    private static func makeHarness(
        opensSheetBy keyStroke: InjectionKeyStroke = .slash,
        readsFocus: Bool = true,
        checksField: Bool = false
    ) -> SequencerHarness {
        let harness = SequencerHarness(
            sheetAppearsAt: nil,
            checksBeforeSubmit: checksField,
            waitsForFieldFocus: checksField,
            fallsBackWhenSheetMissing: true,
            readsFocusForFallback: readsFocus
        )
        harness.keyboard.onRoutedPost = { [harness] posted, route in
            guard posted == keyStroke, route == .systemWide else { return }
            harness.sheetDetector.appearsAt = harness.clock.elapsed + Self.fallbackSheetLatency
            if posted == .slash {
                // / で開いた移動先シートの入力欄には / が入る（macOS 27 の自プロセスのパネルで確認）
                harness.goToField.simulateTyping("/")
            }
        }
        return harness
    }

    private static func keyEntries(_ harness: SequencerHarness) -> [InjectionEventLog.Entry] {
        harness.log.entries.filter { entry in
            if case .key = entry.event { return true }
            return false
        }
    }

    @Test("代替のシート待ちの既定値は 500ms")
    func standardFallbackTiming() {
        #expect(PathInjectionTiming.standard.fallbackSheetWaitLimit == .milliseconds(500))
    }

    @Test("通常は ⌘⇧G・⌘A・⌘V・Return をすべて注入先のプロセスへ送る（他アプリのグローバルホットキーを経由しない）")
    func sendsEveryKeyToTargetProcess() async throws {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), fallsBackWhenSheetMissing: true)

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
            Routed(keyStroke: .returnKey, route: .targetProcess),
        ])
        #expect(harness.sequencer.lastKeyRoute == .targetProcess)
        // シートが出たので代替は使わず、フォーカスも読まない
        #expect(harness.focusReader.readTimes.isEmpty)
    }

    @Test("シートが出なければ、最後の確認（550ms）の後にフォーカスを確かめ、ファイル一覧なら / をシステム経由で送り直す。以降のキーもシステム経由")
    func fallsBackToSlashThroughSystemRoute() async throws {
        let harness = Self.makeHarness()

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .slash, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(harness.focusReader.readTimes == [.milliseconds(550)])
        #expect(Self.keyEntries(harness) == [
            .init(time: .zero, event: .key(.goToFolder)),
            .init(time: .milliseconds(550), event: .key(.slash)),
            .init(time: .milliseconds(700), event: .key(.selectAll)),
            .init(time: .milliseconds(700), event: .key(.paste)),
            .init(time: .milliseconds(800), event: .key(.returnKey)),
        ])
        // 代替を送ってからは 50ms 間隔で確かめ、150ms 後（700ms）に出たシートで続ける
        let checks = harness.log.entries.filter {
            $0.event == .sheetCheck(isShown: false) || $0.event == .sheetCheck(isShown: true)
        }
        #expect(checks.suffix(3).map(\.time) == [.milliseconds(600), .milliseconds(650), .milliseconds(700)])
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test(
        "フォーカスがファイル一覧でなければ（入力欄・その他・読めない）/ は送らず、⌘⇧G をシステム経由で送り直す",
        arguments: [InjectionFocusedElement.textInput, .other, .unavailable]
    )
    func fallsBackToCommandShiftGUnlessFileListIsFocused(focus: InjectionFocusedElement) async throws {
        let harness = Self.makeHarness(opensSheetBy: .goToFolder)
        harness.focusReader.element = focus

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes.prefix(3) == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .goToFolder, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
        ])
        #expect(!harness.log.keyStrokes.contains(.slash))
    }

    @Test("フォーカスを読めない（失敗・100ms の期限切れ）ときも / は送らず、⌘⇧G をシステム経由で送り直す")
    func fallsBackToCommandShiftGWhenFocusIsUnreadable() async throws {
        let failing = Self.makeHarness(opensSheetBy: .goToFolder)
        failing.focusReader.error = AdapterFailure()
        let slow = Self.makeHarness(opensSheetBy: .goToFolder)
        slow.focusReader.latency = .milliseconds(150)

        try await failing.run(path: Self.path)
        try await slow.run(path: Self.path)

        for harness in [failing, slow] {
            #expect(harness.log.keyStrokes.prefix(2) == [.goToFolder, .goToFolder])
            #expect(harness.keyboard.routedKeyStrokes[1] == Routed(keyStroke: .goToFolder, route: .systemWide))
        }
        // 読み取りが期限（550ms + 100ms）を過ぎたら、その時点で打ち切って送る（フェイクの読み取りは 150ms で 1 回の AX 操作）
        #expect(Self.keyEntries(slow)[1].time == .milliseconds(700))
    }

    @Test("フォーカスを読まない構成では、⌘⇧G をシステム経由で送り直す")
    func fallsBackToCommandShiftGWithoutFocusReader() async throws {
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, readsFocus: false)

        try await harness.run(path: Self.path)

        #expect(harness.log.keyStrokes == [.goToFolder, .goToFolder, .selectAll, .paste, .returnKey])
        #expect(harness.focusReader.readTimes.isEmpty)
    }

    @Test("代替でもシートが出なければ、代替の期限（500ms）まで 50ms 間隔で確かめて timeout(waitSheet)。ペーストボードには触れない")
    func timesOutWhenFallbackAlsoFails() async {
        let harness = Self.makeHarness(opensSheetBy: .returnKey)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        let checkTimes = harness.log.entries.filter { $0.event == .sheetCheck(isShown: false) }.map(\.time)
        let firstChecks = (1...11).map { Duration.milliseconds(50 * $0) }
        let fallbackChecks = (0...8).map { Duration.milliseconds(600 + 50 * $0) }
        #expect(checkTimes == firstChecks + fallbackChecks)
        #expect(harness.log.keyStrokes == [.goToFolder, .slash])
        #expect(harness.pasteboard.writes.isEmpty)
        // 副方式が Return を送るときも、システム経由で送る
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
    }

    @Test("判定の走査が期限（600ms）をまたいで打ち切られたら、期限までに出なかったものとして代替を試す")
    func fallsBackWhenScanIsCutOffAtDeadline() async throws {
        let harness = Self.makeHarness()
        harness.sheetDetector.checkLatency = .milliseconds(200)

        try await harness.run(path: Self.path)

        // 50ms に開始・250ms に終了 → 300ms に開始・500ms に終了 → 550ms に開始し、600ms の次の AX 操作の前で打ち切る
        let slash = try #require(Self.keyEntries(harness).first { $0.event == .key(.slash) })
        #expect(slash.time == .milliseconds(600))
        #expect(harness.log.keyStrokes == [.goToFolder, .slash, .selectAll, .paste, .returnKey])
    }

    @Test("判定そのものが失敗したら（AX の失敗）、従来どおり代替を試さずに timeout(waitSheet)（副方式へ）")
    func detectorFailureSkipsFallback() async {
        let harness = Self.makeHarness()
        harness.sheetDetector.checkError = AdapterFailure()

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.focusReader.readTimes.isEmpty)
    }

    @Test("代替を試さない構成では、従来どおり timeout(waitSheet) を投げ、⌘⇧G は注入先のプロセスへ送った 1 回だけ")
    func noFallbackKeepsTimeout() async {
        let harness = SequencerHarness(sheetAppearsAt: nil)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.keyboard.routedKeyStrokes == [Routed(keyStroke: .goToFolder, route: .targetProcess)])
        #expect(harness.sequencer.lastKeyRoute == .targetProcess)
    }

    @Test("代替のキーを送る直前にも注入先を確かめ、最前面でなくなっていれば送らずに targetNotFrontmost")
    func checksTargetBeforeFallbackKey() async {
        let harness = Self.makeHarness()
        harness.targetGuard.invalidation = (fromCheck: 1, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("代替のキーを送った直後にキャンセルされたら、シートを待たずに CancellationError。以降のキーは送らない")
    func cancellationAfterFallbackKey() async {
        let harness = Self.makeHarness()
        harness.keyboard.onPost = { keyStroke in
            if keyStroke == .slash {
                cancelCurrentTask()
            }
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .slash])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("/ で開いたシートの入力欄に / が入っていても、⌘A → ⌘V で置き換え、貼り付けを確かめて Return を送る")
    func replacesSlashInFieldOpenedByFallback() async throws {
        let harness = Self.makeHarness(checksField: true)

        try await harness.run(path: Self.path)

        #expect(harness.goToField.currentValue == Self.path)
        #expect(harness.log.keyStrokes == [.goToFolder, .slash, .selectAll, .paste, .returnKey])
        // 入力欄が / から移動先に変わったのを確かめたため、Return の前にペーストボードを戻す
        let returnIndex = try #require(harness.log.events.firstIndex(of: .key(.returnKey)))
        let restoreIndex = try #require(harness.log.events.lastIndex(of: .pasteboardWrite(.userClipboard)))
        #expect(restoreIndex < returnIndex)
    }

    @Test("注入先のプロセスへ送った ⌘A / ⌘V が入力欄に届かなければ（開いていたシート）、副方式の Return はシステム経由で送るよう切り替える")
    func switchesToSystemRouteWhenPasteDoesNotArrive() async {
        let harness = SequencerHarness(sheetAppearsAt: nil, checksBeforeSubmit: true, waitsForFieldFocus: true, fallsBackWhenSheetMissing: true)
        harness.sheetDetector.isSheetAlreadyShown = true
        // 注入先のプロセスへ送ったキーは入力欄に届かない
        harness.keyboard.onPost = nil

        await #expect(throws: InjectionError.timeout(step: .waitPaste)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .selectAll, route: .targetProcess),
            Routed(keyStroke: .paste, route: .targetProcess),
        ])
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("送り先を決めている（AX を読んでいる）間に注入先が最前面でなくなったら、そのキーを送らずに targetNotFrontmost。ペーストボードは戻す")
    func checksTargetAfterResolvingDestination() async {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150))
        harness.keyboard.onPrepare = { [targetGuard = harness.targetGuard] keyStroke in
            guard keyStroke == .paste else { return }
            targetGuard.invalidation = (fromCheck: targetGuard.checkCount, status: .notFrontmost)
        }

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("送り先を決めている間にキャンセルされたら、そのキーを送らずに CancellationError")
    func checksCancellationAfterResolvingDestination() async {
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150))
        harness.keyboard.onPrepare = { keyStroke in
            if keyStroke == .returnKey {
                cancelCurrentTask()
            }
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .selectAll, .paste])
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("次の注入は、また注入先のプロセスへ送るところから始める")
    func nextInjectionStartsWithTargetProcess() async throws {
        let harness = Self.makeHarness()
        try await harness.run(path: Self.path)
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        harness.keyboard.onRoutedPost = nil
        harness.sheetDetector.appearsAt = .zero

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes.suffix(4).allSatisfy { $0.route == .targetProcess })
        #expect(harness.sequencer.lastKeyRoute == .targetProcess)
    }
}
