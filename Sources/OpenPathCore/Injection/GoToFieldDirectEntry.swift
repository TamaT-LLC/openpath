/// パス注入の副方式（AX 直接セット、DSN-001 §3.2）。
///
/// 主方式が移動先シートを見つけられなかった（`timeout(.waitSheet)`）か、シートは出たが貼り付けの操作に失敗した・
/// 貼り付けたパスが入力欄に入らなかった（`timeout(.waitPaste)`）ときに使う。移動先シートの入力欄を AX で探し直し、
/// 値を直接セットしてから確定する。その後はステップ 8（auto_confirm）へ進む。
///
/// - ペーストボードは使わない。
/// - 確定は「移動」/「Go」ボタンがあれば押し、無ければ Return を送る（macOS 13 以降の移動先シート）。
///   macOS 27 の移動先シートの入力欄は kAXConfirmAction に成功を返すが移動しないため（Issue #74）、
///   入力欄の確定（kAXConfirmAction）は Return を送れなかったときだけ使う。
/// - 確定の前に、入力欄の値と候補の選択が移動先になったかを確かめる（`GoToSheetSubmitGate`）。
///   入力欄の値が移動先にならなければ確定せず、`timeout(.waitPaste)` を投げる。
/// - Return は入力欄に届いて初めて移動先への確定になるため、送る前に入力欄がフォーカスを持つまで待つ（`GoToFieldFocusWait`、Issue #74）。
///   来なければ AX でフォーカスを与えてから送る（与えられなくても送る）。待っている間に入力欄が消えたら（シートが閉じた）、
///   Return がパネルの「開く」に届かないよう送らずに `timeout(.waitPaste)` を投げる。
/// - 入力欄が見つからなければ、主方式の失敗をそのまま投げる。パレットの文言を主方式の失敗理由（⌘⇧G が開かない等）にするため。
/// - 値のセットと確定の直前ごとに注入先を確かめる。
@MainActor
public final class GoToFieldDirectEntry {
    private let locator: any GoToFieldLocating
    private let targetGuard: any InjectionTargetGuarding
    private let keyboard: any KeyStrokePosting
    private let prepareForKeyEvents: PathInjectionHooks.PrepareForKeyEvents
    private let submitGate: GoToSheetSubmitGate?
    private let fieldFocus: GoToFieldFocusWait?
    private let didSubmit: PathInjectionHooks.DidSubmitGoToSheet
    private let timing: PanelControlTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - keyboard: 「移動」ボタンが無いときに Return を送る。
    ///   - prepareForKeyEvents: Return を送る前に呼ぶ（主方式の `PathInjectionHooks.prepareForKeyEvents` と同じもの）。
    ///     主方式が ⌘⇧G を送る前に失敗した場合、パレットがまだキーを持っているため。
    ///   - submitGate: 確定の前に入力欄の値と候補の選択を確かめる。nil なら確かめない。
    ///   - fieldFocus: Return の前に入力欄がフォーカスを持つまで待つ。nil なら待たない。
    ///   - didSubmit: 確定した後に呼ぶ（主方式の `PathInjectionHooks.didSubmitGoToSheet` と同じもの）。
    ///   - clock: 走査の期限の計測に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        targetGuard: any InjectionTargetGuarding,
        keyboard: any KeyStrokePosting,
        prepareForKeyEvents: @escaping PathInjectionHooks.PrepareForKeyEvents = {},
        submitGate: GoToSheetSubmitGate? = nil,
        fieldFocus: GoToFieldFocusWait? = nil,
        didSubmit: @escaping PathInjectionHooks.DidSubmitGoToSheet = { _ in },
        timing: PanelControlTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.targetGuard = targetGuard
        self.keyboard = keyboard
        self.prepareForKeyEvents = prepareForKeyEvents
        self.submitGate = submitGate
        self.fieldFocus = fieldFocus
        self.didSubmit = didSubmit
        self.timing = timing
        self.clock = clock
    }

    /// - Parameter primaryError: 主方式の失敗。入力欄が見つからない・探すのが期限を超えた場合に投げる。
    /// - Throws: `InjectionError`、キャンセル時は `CancellationError`。
    public func run(path: String, autoConfirm: Bool, fallingBackFrom primaryError: InjectionError) async throws {
        try Task.checkCancellation()
        let timeline = ElapsedTimeline(clock: clock)
        let foundControls = try await PanelControlOperation.lookUp(
            within: timing.controlLookupLimit,
            on: timeline,
            failingAs: primaryError
        ) { cutoff in
            try await locator.locateGoToField(cutoff: cutoff)
        }
        guard let controls = foundControls else {
            Log.debug("副方式: 移動先シートの入力欄が見つかりません（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
            throw primaryError
        }

        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        try await PanelControlOperation.setValue(path, on: controls.field)
        Log.debug("副方式: 入力欄に値をセットしました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        try await ensureReadyToSubmit(path: path, controls: controls)
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        if let goButton = controls.goButton {
            try await PanelControlOperation.activate(goButton, by: .press)
            Log.debug("副方式: 「移動」を押しました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        } else {
            try await submitByReturnKey(controls: controls, on: timeline)
        }
        try await didSubmit(autoConfirm)
    }

    private func ensureReadyToSubmit(path: String, controls: GoToFieldControls) async throws {
        guard let submitGate else { return }
        guard try await submitGate.waitUntilReady(path: path, controls: controls) != .fieldMismatch else {
            Log.warning("移動先シートの入力欄にセットしたパスが入っていないため、確定しません")
            throw InjectionError.timeout(step: .waitPaste)
        }
    }

    /// キー入力は注入先のキーウィンドウ（移動先シート）に届く。Return を送れなければ入力欄を確定する。
    private func submitByReturnKey(controls: GoToFieldControls, on timeline: ElapsedTimeline) async throws {
        await prepareForKeyEvents()
        try await waitForFieldFocus(controls: controls, on: timeline)
        // パレットにキーを手放させている間に切り替わっていないか、送る直前に確かめ直す
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        do {
            try keyboard.post(.returnKey)
            Log.debug("副方式: Return を送りました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        } catch {
            Log.debug("副方式: Return を送れなかったため、入力欄を確定します")
            try await PanelControlOperation.activate(controls.field, by: .confirm)
        }
    }

    /// 副方式は Return の他に確定の手段が無い（入力欄の kAXConfirmAction は macOS 27 で移動しない）ため、
    /// フォーカスが来なくても AX で与えてから送る。主方式と違い、送らずに諦めると移動できないまま終わるため。
    private func waitForFieldFocus(controls: GoToFieldControls, on timeline: ElapsedTimeline) async throws {
        guard let fieldFocus else { return }
        let result = try await fieldFocus.waitUntilFocused(controls: controls)
        Log.debug("副方式: 入力欄のフォーカスを待ちました（\(result.focus.rawValue)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        switch result.focus {
        case .focused, .unavailable:
            return
        case .fieldGone:
            // シートごとパネルが閉じていれば、貼り付けの失敗ではなくパネルが消えたことを伝える
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            Log.warning("移動先シートの入力欄が消えたため、Return を送りません")
            throw InjectionError.timeout(step: .waitPaste)
        case .notFocused:
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            do {
                try await controls.field.focus()
                Log.debug("副方式: 入力欄に AX でフォーカスを与えました")
            } catch {
                try Task.checkCancellation()
                Log.debug("副方式: 入力欄に AX でフォーカスを与えられませんでした（\(error)）")
            }
        }
    }
}
