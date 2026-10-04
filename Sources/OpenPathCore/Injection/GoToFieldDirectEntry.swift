/// パス注入の副方式（AX 直接セット、DSN-001 §3.2）。
///
/// 主方式が移動先シートを見つけられなかった（`timeout(.waitSheet)`）か、シートは出たが貼り付けの操作に失敗した・
/// 貼り付けたパスが入力欄に入らなかった（`timeout(.waitPaste)`）か、Return を送っても移動先シートが閉じなかった
/// （`timeout(.waitSheetClose)`、Issue #95）ときに使う。移動先シートの入力欄を AX で探し直し、
/// 値を直接セットしてから確定し、シートが閉じたのを確かめてからステップ 9（auto_confirm）へ進む。
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
/// - 確定の後、移動先シートが閉じるまで最大 600ms 待つ（`GoToSheetCloseWait`、Issue #95）。閉じなければ確定が届いていないため、
///   成功とせずに `timeout(.waitSheetClose)` を投げる（パレットに「「フォルダへ移動」を確定できません」と出る）。
/// - 主方式の Return の後にシートが閉じなかった（`timeout(.waitSheetClose)`）ときの Return は、送る直前に移動先シートが
///   キーウィンドウかを確かめ、そうでなければ送らない（後ろのパネルの「開く」に届かせない。`ensureSheetHasKeyFocus`）。
/// - 入力欄が見つからなければ、主方式の失敗をそのまま投げる。パレットの文言を主方式の失敗理由（⌘⇧G が開かない等）にするため。
///   主方式の失敗が `timeout(.waitSheetClose)` の場合も同じで、主方式が諦めた後にシートが閉じた可能性があっても成功とはしない
///   （一度見つからなかっただけでは閉じたと言い切れず、成功として「開く」を押すと元の場所で開きかねないため）。
/// - 値のセットと確定の直前ごとに注入先を確かめる。
@MainActor
public final class GoToFieldDirectEntry {
    private let locator: any GoToFieldLocating
    private let targetGuard: any InjectionTargetGuarding
    private let keyboard: any KeyStrokePosting
    private let prepareForKeyEvents: PathInjectionHooks.PrepareForKeyEvents
    private let submitGate: GoToSheetSubmitGate?
    private let fieldFocus: GoToFieldFocusWait?
    private let sheetCloseWait: GoToSheetCloseWait?
    private let didSubmit: PathInjectionHooks.DidSubmitGoToSheet
    private let timing: PanelControlTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - keyboard: 「移動」ボタンが無いときに Return を送る。
    ///   - prepareForKeyEvents: Return を送る前に呼ぶ（主方式の `PathInjectionHooks.prepareForKeyEvents` と同じもの）。
    ///     主方式が ⌘⇧G を送る前に失敗した場合、パレットがまだキーを持っているため。
    ///   - submitGate: 確定の前に入力欄の値と候補の選択を確かめる。nil なら確かめない。
    ///   - fieldFocus: Return の前に入力欄がフォーカスを持つまで待つ。nil なら待たない。
    ///   - sheetCloseWait: 確定の後に移動先シートが閉じるのを待つ。nil なら確かめずに、確定したら成功とする。
    ///   - didSubmit: 確定した後に呼ぶ（主方式の `PathInjectionHooks.didSubmitGoToSheet` と同じもの）。
    ///   - clock: 走査の期限の計測に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        targetGuard: any InjectionTargetGuarding,
        keyboard: any KeyStrokePosting,
        prepareForKeyEvents: @escaping PathInjectionHooks.PrepareForKeyEvents = {},
        submitGate: GoToSheetSubmitGate? = nil,
        fieldFocus: GoToFieldFocusWait? = nil,
        sheetCloseWait: GoToSheetCloseWait? = nil,
        didSubmit: @escaping PathInjectionHooks.DidSubmitGoToSheet = { _, _ in },
        timing: PanelControlTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.targetGuard = targetGuard
        self.keyboard = keyboard
        self.prepareForKeyEvents = prepareForKeyEvents
        self.submitGate = submitGate
        self.fieldFocus = fieldFocus
        self.sheetCloseWait = sheetCloseWait
        self.didSubmit = didSubmit
        self.timing = timing
        self.clock = clock
    }

    /// - Parameters:
    ///   - primaryError: 主方式の失敗。入力欄が見つからない・探すのが期限を超えた場合に投げる。
    ///   - keyRoute: Return を送る経路。主方式が最後に使った経路（`GoToFolderPasteSequencer.lastKeyRoute`）を渡す。
    /// - Throws: `InjectionError`、キャンセル時は `CancellationError`。
    public func run(
        path: String,
        autoConfirm: Bool,
        fallingBackFrom primaryError: InjectionError,
        keyRoute: InjectionKeyRoute = .targetProcess
    ) async throws {
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
            if primaryError == .timeout(step: .waitSheetClose) {
                // 主方式が諦めた後にシートが閉じた（主方式の Return は届いていた）可能性があるが、一度見つからなかっただけでは
                // 閉じたと言い切れない。成功とはせず、閉じたシートの後ろのパネルへ Return を送らないよう確定し直しもしない
                Log.info("副方式: 主方式の Return の後に移動先シートの入力欄が見つからなくなりました。閉じたかを確かめられないため、確定し直さずに失敗とします（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
                throw primaryError
            }
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
            try await submitByReturnKey(
                controls: controls,
                via: keyRoute,
                requiresSheetKeyFocus: primaryError == .timeout(step: .waitSheetClose),
                on: timeline
            )
        }
        let submittedAt = timeline.elapsed
        try await ensureSheetClosed(controls, on: timeline)
        try await didSubmit(autoConfirm, timeline.elapsed - submittedAt)
    }

    /// 「移動」の押下・Return が移動先シートに届かなければ、シートは残りパネルは移動しない（Issue #95）。
    /// 閉じたのを確かめてから成功とし、閉じない・閉じたことを確かめられなければ `timeout(.waitSheetClose)` を投げる（パレットに出す）。
    private func ensureSheetClosed(_ controls: GoToFieldControls, on timeline: ElapsedTimeline) async throws {
        guard let sheetCloseWait else { return }
        let closure = try await sheetCloseWait.waitUntilClosed(controls: controls)
        Log.debug("副方式: 移動先シートが閉じたかを確かめました（\(closure.rawValue)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        guard closure != .closed else { return }
        Log.warning("副方式で確定しても移動先シートが閉じたことを確かめられない（\(closure.rawValue)）ため、移動できませんでした")
        throw InjectionError.timeout(step: .waitSheetClose)
    }

    private func ensureReadyToSubmit(path: String, controls: GoToFieldControls) async throws {
        guard let submitGate else { return }
        guard try await submitGate.waitUntilReady(path: path, controls: controls) != .fieldMismatch else {
            Log.warning("移動先シートの入力欄にセットしたパスが入っていないため、確定しません")
            throw InjectionError.timeout(step: .waitPaste)
        }
    }

    /// キー入力は注入先のキーウィンドウ（移動先シート）に届く。Return を送れなければ入力欄を確定する。
    /// - Parameter requiresSheetKeyFocus: 送る直前に、移動先シートがキーウィンドウかを確かめるか（主方式の Return の後にシートが
    ///   閉じなかった場合。`ensureSheetHasKeyFocus`）。
    private func submitByReturnKey(
        controls: GoToFieldControls,
        via route: InjectionKeyRoute,
        requiresSheetKeyFocus: Bool,
        on timeline: ElapsedTimeline
    ) async throws {
        await prepareForKeyEvents()
        try await waitForFieldFocus(controls: controls, on: timeline)
        // 送り先を決める（AX の読み取りを伴う）準備は確認の前に済ませ、確認の後は待ちを挟まずに送る
        let prepared = try await prepareReturnKey(via: route)
        // パレットにキーを手放させている間に切り替わっていないか、送る直前に確かめ直す
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        guard let prepared else {
            Log.debug("副方式: Return を送れなかったため、入力欄を確定します")
            try await PanelControlOperation.activate(controls.field, by: .confirm)
            return
        }
        // 注入先の確認はパネル自体にフォーカスがあっても通るため、移動先シートの確認は最後に行い、その後は待たずに送る
        if requiresSheetKeyFocus {
            try await ensureSheetHasKeyFocus(on: timeline)
        }
        try Task.checkCancellation()
        prepared.post()
        Log.debug("副方式: Return を送りました（経路: \(route.rawValue)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
    }

    /// 主方式の Return の後にシートが閉じなかった（`timeout(.waitSheetClose)`）ため Return を送り直すときは、注入先の確認の後、
    /// 送る直前に（間に待ちを挟まずに）、注入先のフォーカス中のウィンドウが移動先シートかを確かめる。
    /// 入力欄の kAXFocused はシートがキーウィンドウかを反映せず、注入先の確認はパネル自体にフォーカスがあっても通る。
    /// 主方式の Return が遅れて届いてシートが閉じかけている・キーウィンドウでなくなっていると、システム経由の Return が
    /// 後ろのパネルの「開く」に届き、移動していない元の場所で開いてしまうため（PR #118 のレビュー）。
    /// 移動先シートでない・確かめられなければ、Return を送らずに `timeout(.waitSheetClose)` を投げる。
    private func ensureSheetHasKeyFocus(on timeline: ElapsedTimeline) async throws {
        let hasKeyFocus = try await InjectionTargetCheck.goToSheetHasFocus(targetGuard, on: timeline)
        Log.debug("副方式: 移動先シートがキーウィンドウかを確かめました（\(hasKeyFocus.map(String.init) ?? "確かめられない")、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        guard hasKeyFocus != true else { return }
        Log.warning("副方式: 移動先シートがキーウィンドウでない・確かめられないため、Return を送らずに失敗とします")
        throw InjectionError.timeout(step: .waitSheetClose)
    }

    /// - Returns: Return を送れない（キーイベントを作れない・送り先を決められない）場合は nil。
    /// - Throws: キャンセル時は `CancellationError`。
    private func prepareReturnKey(via route: InjectionKeyRoute) async throws -> PreparedKeyStroke? {
        try Task.checkCancellation()
        do {
            return try await keyboard.prepare(.returnKey, via: route)
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    /// 副方式は Return の他に確定の手段が無い（入力欄の kAXConfirmAction は macOS 27 で移動しない）ため、
    /// フォーカスが来なければ AX で与える。与えても入力欄が持たなければ、Return はキーウィンドウの別の要素
    /// （パネルの「開く」等）に届いて別の場所で確定しかねないため、送らずに `timeout(.waitPaste)` を投げる。
    /// フォーカスを読めない場合は確かめられないため、従来どおり送る。
    private func waitForFieldFocus(controls: GoToFieldControls, on timeline: ElapsedTimeline) async throws {
        guard let fieldFocus else { return }
        var focus = try await fieldFocus.waitUntilFocused(controls: controls).focus
        Log.debug("副方式: 入力欄のフォーカスを待ちました（\(focus.rawValue)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        if focus == .notFocused {
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            focus = try await fieldFocus.requestFocus(of: controls)
            Log.debug("副方式: 入力欄に AX でフォーカスを与えました（\(focus.rawValue)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        }
        switch focus {
        case .focused, .unavailable:
            return
        case .notFocused, .fieldGone:
            // シートごとパネルが閉じていれば、貼り付けの失敗ではなくパネルが消えたことを伝える
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            Log.warning("移動先シートの入力欄がキー入力を受け取れない（\(focus.rawValue)）ため、Return を送りません")
            throw InjectionError.timeout(step: .waitPaste)
        }
    }
}
