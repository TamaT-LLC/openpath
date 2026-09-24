import OpenPathCore

/// GoToFolderPasteSequencer とテストダブル一式を組み立てる。
@MainActor
final class SequencerHarness {
    /// MainActor に積まれた後続ジョブを先に走らせるための譲り回数（CoordinatorHarness と同じ考え方）。
    private static let drainIterations = 20

    let clock = VirtualClock()
    let log: InjectionEventLog
    let pasteboard: FakePasteboard
    let keyboard: KeyboardSpy
    let sheetDetector: SheetDetectorFake
    let targetGuard: TargetGuardFake
    let hooks: HooksSpy
    /// 移動先シートの入力欄。⌘V でそのときのペーストボードの文字列が入る（checksBeforeSubmit のときだけ確定前の確認が読む）。
    let goToField: PanelElementFake
    let suggestions = SuggestionListFake()
    let goToFieldLocator: GoToFieldLocatorFake
    let sequencer: GoToFolderPasteSequencer

    /// ⌘⇧G で開いた移動先シートの入力欄に、最初から入っている前回の移動先。
    static let previousGoToPath = "/Users/me/前回の場所"

    /// - Parameters:
    ///   - sheetAppearsAt: この経過時間以降の判定で移動先シートが出たことにする。nil なら出ない。
    ///   - clipboard: 注入前にユーザーがコピーしていた内容。
    ///   - checksBeforeSubmit: Return の前に入力欄の値と候補の選択を確かめるか（`GoToSheetSubmitGate`、Issue #74）。
    init(
        sheetAppearsAt: Duration? = .milliseconds(150),
        clipboard: PasteboardSnapshot = .userClipboard,
        checksBeforeSubmit: Bool = false
    ) {
        let log = InjectionEventLog(clock: clock)
        let pasteboard = FakePasteboard(contents: clipboard)
        pasteboard.onWrite = { log.record(.pasteboardWrite($0)) }
        self.log = log
        self.pasteboard = pasteboard
        keyboard = KeyboardSpy(log: log)
        sheetDetector = SheetDetectorFake(clock: clock, log: log, appearsAt: sheetAppearsAt)
        targetGuard = TargetGuardFake(log: log)
        hooks = HooksSpy(clock: clock, log: log)
        goToField = PanelElementFake("path", log: log)
        goToField.simulateTyping(Self.previousGoToPath)
        goToFieldLocator = GoToFieldLocatorFake(clock: clock, log: log)
        goToFieldLocator.logsLookups = false
        goToFieldLocator.field = goToField
        goToFieldLocator.suggestionList = suggestions
        if checksBeforeSubmit {
            // ⌘V で、そのときのペーストボードの文字列が入力欄に入る（OS の貼り付けを再現する）
            keyboard.onPost = { [goToField, pasteboard] keyStroke in
                guard keyStroke == .paste else { return }
                goToField.simulateTyping(pasteboard.contents.plainText)
            }
        }
        sequencer = GoToFolderPasteSequencer(
            pasteboard: pasteboard,
            keyboard: keyboard,
            sheetDetector: sheetDetector,
            targetGuard: targetGuard,
            submitGate: checksBeforeSubmit
                ? GoToSheetSubmitGate(
                    locator: goToFieldLocator,
                    normalizer: InjectionPathNormalizer(homeDirectory: "/Users/me"),
                    clock: clock
                )
                : nil,
            hooks: hooks.hooks,
            timing: .standard,
            clock: clock
        )
    }

    func run(path: String, autoConfirm: Bool = false) async throws {
        try await sequencer.run(path: path, autoConfirm: autoConfirm)
    }

    /// 別の Task で注入を始める（外からのキャンセルを試すため）。
    func startRun(path: String, autoConfirm: Bool = false) -> Task<Void, any Error> {
        Task { [sequencer] in
            try await sequencer.run(path: path, autoConfirm: autoConfirm)
        }
    }

    /// 「まだ何も起きていないこと」を確かめる前に、保留中の MainActor ジョブを処理させる。
    func drainMainActor() async {
        for _ in 0..<Self.drainIterations {
            await Task.yield()
        }
    }
}
