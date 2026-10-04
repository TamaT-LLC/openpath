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
    /// ⌘⇧G でシートが出なかったときの代替が読む、フォーカス中の要素（fallsBackWhenSheetMissing のときだけ使う）。
    let focusReader: FocusReaderFake
    let sequencer: GoToFolderPasteSequencer
    /// Return が届いて移動先シートを閉じるか（送った経路ごと）。既定はどの経路でも閉じる（Issue #95）。
    var returnClosesSheet: (InjectionKeyRoute) -> Bool = { _ in true }
    /// Return が届いてから移動先シートが閉じる（入力欄が消える）までの時間。
    var sheetCloseDelay: Duration = .zero

    /// ⌘⇧G で開いた移動先シートの入力欄に、最初から入っている前回の移動先。
    static let previousGoToPath = "/Users/me/前回の場所"

    /// - Parameters:
    ///   - sheetAppearsAt: この経過時間以降の判定で移動先シートが出たことにする。nil なら出ない。
    ///   - clipboard: 注入前にユーザーがコピーしていた内容。
    ///   - checksBeforeSubmit: Return の前に入力欄の値と候補の選択を確かめるか（`GoToSheetSubmitGate`、Issue #74）。
    ///   - waitsForFieldFocus: ⌘A / ⌘V の前に入力欄がフォーカスを持つまで待つか（`GoToFieldFocusWait`、Issue #74）。
    ///   - fallsBackWhenSheetMissing: 注入先のプロセスへ送った ⌘⇧G でシートが出なければ代替を試すか（`GoToSheetFallback`）。
    ///   - readsFocusForFallback: 代替で、フォーカス中の要素を読んで / を使うか。false なら ⌘⇧G だけを送り直す。
    ///   - routeMemory: 注入先のプロセスへの ⌘⇧G でシートが出なかった注入先の記憶。注入先の識別は `targetGuard.identity`。
    init(
        sheetAppearsAt: Duration? = .milliseconds(150),
        clipboard: PasteboardSnapshot = .userClipboard,
        checksBeforeSubmit: Bool = false,
        waitsForFieldFocus: Bool = false,
        fallsBackWhenSheetMissing: Bool = false,
        readsFocusForFallback: Bool = true,
        routeMemory: GoToSheetRouteMemory? = nil
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
        focusReader = FocusReaderFake(clock: clock)
        if checksBeforeSubmit || waitsForFieldFocus {
            // ⌘V で、そのときのペーストボードの文字列が入力欄に入る（OS の貼り付けを再現する）。
            // キー入力はフォーカスを持つ要素に届くため、入力欄がフォーカスを持っていなければ入らない
            keyboard.onPost = { [goToField, pasteboard] keyStroke in
                guard keyStroke == .paste, goToField.isFocusedNow else { return }
                goToField.simulateTyping(pasteboard.contents.plainText)
            }
        }
        sequencer = GoToFolderPasteSequencer(
            pasteboard: pasteboard,
            keyboard: keyboard,
            sheetDetector: sheetDetector,
            targetGuard: targetGuard,
            fieldFocus: waitsForFieldFocus ? GoToFieldFocusWait(locator: goToFieldLocator, clock: clock) : nil,
            submitGate: checksBeforeSubmit
                ? GoToSheetSubmitGate(
                    locator: goToFieldLocator,
                    normalizer: InjectionPathNormalizer(homeDirectory: "/Users/me"),
                    clock: clock
                )
                : nil,
            // 入力欄を見つける構成（waitsForFieldFocus）でだけ、閉じたかを確かめられる（見つけていなければ確かめない）
            sheetCloseWait: GoToSheetCloseWait(locator: goToFieldLocator, clock: clock),
            sheetFallback: fallsBackWhenSheetMissing
                ? GoToSheetFallback(
                    focusReader: readsFocusForFallback ? focusReader : nil,
                    routeMemory: routeMemory,
                    targetIdentity: { [targetGuard] in targetGuard.identity }
                )
                : nil,
            hooks: hooks.hooks,
            timing: .standard,
            clock: clock
        )
        keyboard.onPostForSheet = { [unowned self] keyStroke, route in
            switch keyStroke {
            case .returnKey where returnClosesSheet(route):
                closeGoToSheet(after: sheetCloseDelay)
            case .goToFolder, .slash:
                // 次の注入の ⌘⇧G・/ で、閉じた移動先シートが開き直す
                reopenGoToSheet()
            default:
                break
            }
        }
    }

    /// 移動先シートを閉じる（delay 後に入力欄が消え、探しても見つからなくなる）。
    func closeGoToSheet(after delay: Duration = .zero) {
        let closesAt = clock.elapsed + delay
        let clock = clock
        let isClosed: @MainActor () -> Bool = { clock.elapsed >= closesAt }
        let field = goToField
        goToField.isGoneProvider = isClosed
        goToFieldLocator.fieldProvider = { isClosed() ? nil : field }
    }

    /// 閉じた移動先シートを開き直す。
    func reopenGoToSheet() {
        goToField.isGoneProvider = nil
        goToFieldLocator.fieldProvider = nil
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
