import Testing

import OpenPathCore

/// 移動先シートを開く 3 段（① 注入先のプロセスへの ⌘⇧G → ② システム経由の / → ③ システム経由の ⌘⇧G）と、
/// ① でシートが出なかった注入先の記憶（Issue #29: macOS 26 の VS Code のリモートのパネルで、① が届かなかった）。
@Suite("GoToFolderPasteSequencer: 移動先シートを 3 段で開き、① で出なかった注入先を覚える", .timeLimit(.minutes(1)))
@MainActor
struct GoToFolderPasteSequencerSheetStageTests {
    private typealias Routed = KeyboardSpy.RoutedKeyStroke

    private static let path = "/Users/me/Library"
    private static let editor = InjectionTargetIdentity(bundleIdentifier: "com.example.editor", processID: 501)
    private static let otherApp = InjectionTargetIdentity(bundleIdentifier: "com.example.other", processID: 502)
    /// システム経由のキーを送ってから移動先シートが出るまでの時間。
    private static let sheetLatency: Duration = .milliseconds(150)

    /// 注入先のプロセスへ送ったキーは届かず、`opener` のキーをシステム経由で送ったときだけ、その 150ms 後に移動先シートが出る。
    /// - Parameter opener: シートを開くキー。nil ならどのキーでも出ない。
    private static func makeHarness(
        opensSheetBy opener: InjectionKeyStroke?,
        focus: InjectionFocusedElement,
        routeMemory: GoToSheetRouteMemory? = nil,
        identity: InjectionTargetIdentity? = editor
    ) -> SequencerHarness {
        let harness = SequencerHarness(sheetAppearsAt: nil, fallsBackWhenSheetMissing: true, routeMemory: routeMemory)
        harness.focusReader.element = focus
        harness.targetGuard.identity = identity
        harness.keyboard.onRoutedPost = { [harness] posted, route in
            guard posted == opener, route == .systemWide else { return }
            harness.sheetDetector.appearsAt = harness.clock.elapsed + Self.sheetLatency
        }
        return harness
    }

    private static func keyEntries(_ harness: SequencerHarness) -> [InjectionEventLog.Entry] {
        harness.log.entries.filter { entry in
            if case .key = entry.event { return true }
            return false
        }
    }

    private static func sheetCheckTimes(_ harness: SequencerHarness) -> [Duration] {
        harness.log.entries.filter { $0.event == .sheetCheck(isShown: false) || $0.event == .sheetCheck(isShown: true) }.map(\.time)
    }

    // MARK: - 待ち時間

    @Test("各段のシート待ちの既定値は ① 200ms・② 300ms・③ 500ms。代替の無い構成と基準の走査は従来どおり 600ms")
    func standardStageTiming() {
        let timing = PathInjectionTiming.standard

        #expect(timing.targetProcessSheetWaitLimit == .milliseconds(200))
        #expect(timing.slashSheetWaitLimit == .milliseconds(300))
        #expect(timing.systemGoToSheetWaitLimit == .milliseconds(500))
        #expect(timing.sheetWaitLimit == .milliseconds(600))
    }

    // MARK: - 3 段

    @Test("フォーカスがファイル一覧でなければ ② を飛ばし、① の最後の確認（150ms）の後に ③ をシステム経由で送る。以降のキーもシステム経由")
    func opensThroughSystemGoToWhenFileListIsNotFocused() async throws {
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, focus: .other)

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .goToFolder, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(Self.keyEntries(harness) == [
            .init(time: .zero, event: .key(.goToFolder)),
            .init(time: .milliseconds(150), event: .key(.goToFolder)),
            .init(time: .milliseconds(300), event: .key(.selectAll)),
            .init(time: .milliseconds(300), event: .key(.paste)),
            .init(time: .milliseconds(400), event: .key(.returnKey)),
        ])
        #expect(harness.focusReader.readTimes == [.milliseconds(150)])
        #expect(Self.sheetCheckTimes(harness) == [50, 100, 150, 200, 250, 300].map { Duration.milliseconds($0) })
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test("フォーカスがファイル一覧で ② の / でも出なければ、② の最後の確認（400ms）の後に ③ をシステム経由で送る")
    func opensThroughSystemGoToWhenSlashFails() async throws {
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, focus: .fileList)

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .slash, route: .systemWide),
            Routed(keyStroke: .goToFolder, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        #expect(Self.keyEntries(harness) == [
            .init(time: .zero, event: .key(.goToFolder)),
            .init(time: .milliseconds(150), event: .key(.slash)),
            .init(time: .milliseconds(400), event: .key(.goToFolder)),
            .init(time: .milliseconds(550), event: .key(.selectAll)),
            .init(time: .milliseconds(550), event: .key(.paste)),
            .init(time: .milliseconds(650), event: .key(.returnKey)),
        ])
        // フォーカスは ② の前に 1 回だけ読む（③ は / を送らないため読み直さない）
        #expect(harness.focusReader.readTimes == [.milliseconds(150)])
    }

    @Test("② の / でシートが出たら、③ の ⌘⇧G は送らない")
    func skipsSystemGoToWhenSlashOpensSheet() async throws {
        let harness = Self.makeHarness(opensSheetBy: .slash, focus: .fileList)

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes.prefix(3) == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .slash, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
        ])
        #expect(!harness.keyboard.routedKeyStrokes.contains(Routed(keyStroke: .goToFolder, route: .systemWide)))
    }

    @Test("どの段でも出なければ、③ の期限（500ms）まで確かめて timeout(waitSheet)。ペーストボードには触れない")
    func timesOutWhenNoStageOpensSheet() async {
        let harness = Self.makeHarness(opensSheetBy: nil, focus: .fileList)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.keyboard.routedKeyStrokes == [
            Routed(keyStroke: .goToFolder, route: .targetProcess),
            Routed(keyStroke: .slash, route: .systemWide),
            Routed(keyStroke: .goToFolder, route: .systemWide),
        ])
        let first = [50, 100, 150]
        let slash = [200, 250, 300, 350, 400]
        let systemGoTo = (0...8).map { 450 + 50 * $0 }
        #expect(Self.sheetCheckTimes(harness) == (first + slash + systemGoTo).map { Duration.milliseconds($0) })
        #expect(harness.pasteboard.writes.isEmpty)
        // 副方式が Return を送るときも、システム経由で送る
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
    }

    @Test("③ の ⌘⇧G を送る直前にも注入先を確かめ、最前面でなくなっていれば送らずに targetNotFrontmost")
    func checksTargetBeforeSystemGoTo() async {
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, focus: .fileList)
        // 0: ① の ⌘⇧G、1: ② の /、2: ③ の ⌘⇧G
        harness.targetGuard.invalidation = (fromCheck: 2, status: .notFrontmost)

        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .slash])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("③ の ⌘⇧G を送った直後にキャンセルされたら、シートを待たずに CancellationError。以降のキーは送らない")
    func cancellationAfterSystemGoTo() async {
        let harness = Self.makeHarness(opensSheetBy: nil, focus: .fileList)
        harness.keyboard.onRoutedPost = { keyStroke, route in
            if keyStroke == .goToFolder, route == .systemWide {
                cancelCurrentTask()
            }
        }

        await #expect(throws: CancellationError.self) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.log.keyStrokes == [.goToFolder, .slash, .goToFolder])
        #expect(harness.pasteboard.writes.isEmpty)
    }

    // MARK: - 経路の記憶

    @Test("① で出なかった注入先は、次の注入で ① を飛ばし、待たずに ③ から始める。別の注入先は ① から")
    func skipsTargetProcessRouteForRememberedTarget() async throws {
        let memory = GoToSheetRouteMemory()
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, focus: .other, routeMemory: memory)
        try await harness.run(path: Self.path)
        #expect(memory.skipsTargetProcessRoute(for: Self.editor))

        let secondStart = harness.clock.elapsed
        let secondFrom = harness.keyboard.routedKeyStrokes.count
        try await harness.run(path: Self.path)

        #expect(Array(harness.keyboard.routedKeyStrokes[secondFrom...]) == [
            Routed(keyStroke: .goToFolder, route: .systemWide),
            Routed(keyStroke: .selectAll, route: .systemWide),
            Routed(keyStroke: .paste, route: .systemWide),
            Routed(keyStroke: .returnKey, route: .systemWide),
        ])
        let secondGoTo = Self.keyEntries(harness)[secondFrom]
        #expect(secondGoTo == .init(time: secondStart, event: .key(.goToFolder)))

        harness.targetGuard.identity = Self.otherApp
        let thirdFrom = harness.keyboard.routedKeyStrokes.count
        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes[thirdFrom] == Routed(keyStroke: .goToFolder, route: .targetProcess))
    }

    @Test("覚えた注入先でもフォーカスがファイル一覧なら、② の / から始める")
    func rememberedTargetStartsWithSlashWhenFileListIsFocused() async throws {
        let memory = GoToSheetRouteMemory()
        memory.recordTargetProcessRouteMissed(for: Self.editor)
        let harness = Self.makeHarness(opensSheetBy: .slash, focus: .fileList, routeMemory: memory)

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes.first == Routed(keyStroke: .slash, route: .systemWide))
        #expect(Self.keyEntries(harness).first == .init(time: .zero, event: .key(.slash)))
        #expect(!harness.keyboard.routedKeyStrokes.contains { $0.route == .targetProcess })
    }

    @Test("覚えた注入先で ② / ③ でも出なければ忘れ、次の注入はまた ① から試す")
    func forgetsRememberedTargetWhenSystemRouteAlsoFails() async {
        let memory = GoToSheetRouteMemory()
        memory.recordTargetProcessRouteMissed(for: Self.editor)
        let harness = Self.makeHarness(opensSheetBy: nil, focus: .other, routeMemory: memory)

        await #expect(throws: InjectionError.timeout(step: .waitSheet)) {
            try await harness.run(path: Self.path)
        }

        #expect(harness.keyboard.routedKeyStrokes == [Routed(keyStroke: .goToFolder, route: .systemWide)])
        #expect(!memory.skipsTargetProcessRoute(for: Self.editor))
        #expect(harness.sequencer.lastKeyRoute == .systemWide)
    }

    @Test("① でシートが出たら覚えない")
    func doesNotRememberWhenTargetProcessRouteOpensSheet() async throws {
        let memory = GoToSheetRouteMemory()
        let harness = SequencerHarness(sheetAppearsAt: .milliseconds(150), fallsBackWhenSheetMissing: true, routeMemory: memory)
        harness.targetGuard.identity = Self.editor

        try await harness.run(path: Self.path)

        #expect(!memory.skipsTargetProcessRoute(for: Self.editor))
        #expect(harness.keyboard.routedKeyStrokes.allSatisfy { $0.route == .targetProcess })
    }

    @Test("注入先を識別できなければ覚えず、次の注入も ① から試す")
    func doesNotRememberUnidentifiedTarget() async throws {
        let memory = GoToSheetRouteMemory()
        let harness = Self.makeHarness(opensSheetBy: .goToFolder, focus: .other, routeMemory: memory, identity: nil)
        try await harness.run(path: Self.path)
        let secondFrom = harness.keyboard.routedKeyStrokes.count

        try await harness.run(path: Self.path)

        #expect(harness.keyboard.routedKeyStrokes[secondFrom] == Routed(keyStroke: .goToFolder, route: .targetProcess))
    }
}
