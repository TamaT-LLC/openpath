import OpenPathCore

/// PathInjectionFlow を、主方式・副方式・auto_confirm の実物とテストダブル一式で組み立てる（PanelInjector と同じ組み合わせ）。
@MainActor
final class FlowHarness {
    static let homeDirectory = "/Users/me"
    /// MainActor に積まれた後続ジョブを先に走らせるための譲り回数（SequencerHarness と同じ考え方）。
    private static let drainIterations = 20

    let clock = VirtualClock()
    let log: InjectionEventLog
    let pasteboard: FakePasteboard
    let keyboard: KeyboardSpy
    let sheetDetector: SheetDetectorFake
    let targetGuard: TargetGuardFake
    let goToField: PanelElementFake
    let goButton: PanelElementFake
    let openButton: PanelElementFake
    let goToFieldLocator: GoToFieldLocatorFake
    /// 主方式の確定前の確認が入力欄を探す先（副方式の探し方と区別するため、探したことをログに残さない）。
    let submitCheckLocator: GoToFieldLocatorFake
    let openButtonLocator: OpenButtonLocatorFake
    let flow: PathInjectionFlow

    /// - Parameter sheetAppearsAt: この経過時間以降の判定で移動先シートが出たことにする。nil なら出ない（副方式へ）。
    init(sheetAppearsAt: Duration? = .milliseconds(150), clipboard: PasteboardSnapshot = .userClipboard) {
        let log = InjectionEventLog(clock: clock)
        let pasteboard = FakePasteboard(contents: clipboard)
        pasteboard.onWrite = { log.record(.pasteboardWrite($0)) }
        self.log = log
        self.pasteboard = pasteboard
        keyboard = KeyboardSpy(log: log)
        sheetDetector = SheetDetectorFake(clock: clock, log: log, appearsAt: sheetAppearsAt)
        targetGuard = TargetGuardFake(log: log)
        goToField = PanelElementFake("path", log: log)
        goButton = PanelElementFake("go", log: log)
        openButton = PanelElementFake("open", log: log)
        goToFieldLocator = GoToFieldLocatorFake(clock: clock, log: log)
        goToFieldLocator.field = goToField
        goToFieldLocator.goButton = goButton
        submitCheckLocator = GoToFieldLocatorFake(clock: clock, log: log)
        submitCheckLocator.logsLookups = false
        submitCheckLocator.field = goToField
        openButtonLocator = OpenButtonLocatorFake(clock: clock, log: log)
        openButtonLocator.button = openButton
        // ⌘V で、そのときのペーストボードの文字列が入力欄に入る（OS の貼り付けを再現する）。
        // キー入力はフォーカスを持つ要素に届くため、入力欄がフォーカスを持っていなければ入らない
        keyboard.onPost = { [goToField, pasteboard] keyStroke in
            guard keyStroke == .paste, goToField.isFocusedNow else { return }
            goToField.simulateTyping(pasteboard.contents.plainText)
        }

        let autoConfirm = OpenButtonAutoConfirm(locator: openButtonLocator, targetGuard: targetGuard, clock: clock)
        let didSubmit: PathInjectionHooks.DidSubmitGoToSheet = { isAutoConfirm in
            log.record(.didSubmitGoToSheet(autoConfirm: isAutoConfirm))
            try await autoConfirm.confirm(autoConfirm: isAutoConfirm)
        }
        let prepareForKeyEvents: PathInjectionHooks.PrepareForKeyEvents = { log.record(.prepareForKeyEvents) }
        let normalizer = InjectionPathNormalizer(homeDirectory: Self.homeDirectory)
        // PanelInjector と同じく、主方式と副方式で同じ待ち方を使う（主方式は探したことをログに残さない探し方で探す）
        let primaryFieldFocus = GoToFieldFocusWait(locator: submitCheckLocator, clock: clock)
        let secondaryFieldFocus = GoToFieldFocusWait(locator: goToFieldLocator, clock: clock)
        flow = PathInjectionFlow(
            targetGuard: targetGuard,
            primary: GoToFolderPasteSequencer(
                pasteboard: pasteboard,
                keyboard: keyboard,
                sheetDetector: sheetDetector,
                targetGuard: targetGuard,
                fieldFocus: primaryFieldFocus,
                submitGate: GoToSheetSubmitGate(locator: submitCheckLocator, normalizer: normalizer, clock: clock),
                hooks: PathInjectionHooks(prepareForKeyEvents: prepareForKeyEvents, didSubmitGoToSheet: didSubmit),
                clock: clock
            ),
            secondary: GoToFieldDirectEntry(
                locator: goToFieldLocator,
                targetGuard: targetGuard,
                keyboard: keyboard,
                prepareForKeyEvents: prepareForKeyEvents,
                submitGate: GoToSheetSubmitGate(locator: goToFieldLocator, normalizer: normalizer, clock: clock),
                fieldFocus: secondaryFieldFocus,
                didSubmit: didSubmit,
                clock: clock
            ),
            normalizer: normalizer,
            clock: clock
        )
    }

    func run(path: String, autoConfirm: Bool = false) async throws {
        try await flow.run(path: path, autoConfirm: autoConfirm)
    }

    /// 別の Task で注入を始める（外からのキャンセルや直列化を試すため）。
    func startRun(path: String, autoConfirm: Bool = false) -> Task<Void, any Error> {
        Task { [flow] in
            try await flow.run(path: path, autoConfirm: autoConfirm)
        }
    }

    /// 「まだ何も起きていないこと」を確かめる前に、保留中の MainActor ジョブを処理させる。
    func drainMainActor() async {
        for _ in 0..<Self.drainIterations {
            await Task.yield()
        }
    }

    /// 入力欄・ボタンへの AX 操作（値のセット・押下・確定）。
    var elementOperations: [InjectionEventLog.Event] {
        log.events.filter { event in
            switch event {
            case .setValue, .press, .confirmField: true
            default: false
            }
        }
    }
}
