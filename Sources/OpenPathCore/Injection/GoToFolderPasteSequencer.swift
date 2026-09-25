/// パス注入の主方式（⌘⇧G + ペースト）の手順を実行する（DSN-001 §3.1、ARCH-001 §7）。
///
/// 手順（括弧内は DSN-001 §3.1 のステップ番号）:
/// 1. 移動先シートの判定基準を記録する（`GoToSheetDetecting.makeProbe`）
/// 2. `hooks.prepareForKeyEvents` でキー入力を NSOpenPanel へ向ける
/// 3. ⌘⇧G を送り（3）、最大 600ms・50ms 間隔でシートの出現を待つ（4）
/// 4. 移動先シートの入力欄がフォーカスを持つまで最大 250ms 待つ（`GoToFieldFocusWait`、Issue #74）。
///    来なければ（入力欄が消えた場合も）ペーストボードに触れずに `timeout(.waitPaste)` を投げる（副方式へ）
/// 5. ペーストボードを退避してパスを書き込み（1, 2）、⌘A → ⌘V（5）
/// 6. 100ms 待って（6）、移動先シートの入力欄の値と候補の選択が移動先になったかを確かめてから（`GoToSheetSubmitGate`、Issue #74）
///    Return を送る（7）。入力欄の値が移動先にならなければ Return を送らず `timeout(.waitPaste)` を投げる（副方式へ）。
///    送る直前にも、確かめた入力欄がまだフォーカスを持つかを確かめ、持たなければ同じく副方式へ回す
/// 7. `hooks.didSubmitGoToSheet`（8: auto_confirm の差し込み口）
/// 8. Return から 200ms 後にペーストボードを戻す（9）。ただし確定前の確認で、貼り付けで入力欄が別の値から移動先に変わったことを
///    確かめられたら、⌘V は処理済みのため Return の前に戻して待たない（Issue #74）
///
/// - ペーストボードは差し替えた後なら、成功・失敗・キャンセルのどの経路でも戻す。
///   失敗・キャンセル時は 200ms を待たずにすぐ戻す。戻せなければ `InjectionError.pasteboardRestoreFailed` を投げる。
///   元の内容が機密（パスワードマネージャー等）なら戻さずに空にする（`PasteboardSwap`。失敗ではない）。
/// - キーを送る直前ごとに注入先がまだ有効か（アプリが最前面で、ウィンドウが残っているか）を確かめ、
///   無効なら送らずに `.targetNotFrontmost` / `.panelGone` を投げる。注入先の記録は呼び出し元（`PathInjectionFlow`）が行う。
/// - キャンセルには各ステップの間と待機中に応じ、以降のキー操作は送らない。
/// - AX の走査には期限（600ms）を設け、期限の到来かキャンセルで AX 操作の合間に打ち切る（`ScanCutoff`）。
/// - 前の注入が後始末を終えるまで、次の注入は始めない（`InjectionSerialGate`）。
/// - 各ステップを経過時間付きで debug ログに残す（Issue #74 の切り分け用）。
@MainActor
public final class GoToFolderPasteSequencer {
    private let pasteboard: any PasteboardAccessing
    private let keyboard: any KeyStrokePosting
    private let sheetDetector: any GoToSheetDetecting
    private let targetGuard: any InjectionTargetGuarding
    private let fieldFocus: GoToFieldFocusWait?
    private let submitGate: GoToSheetSubmitGate?
    private let hooks: PathInjectionHooks
    private let timing: PathInjectionTiming
    private let clock: any Clock<Duration>
    private let gate = InjectionSerialGate()

    /// - Parameters:
    ///   - targetGuard: キーを送る直前ごとに注入先を確かめる。配線漏れで誤送出を防げなくならないよう、既定値を持たせない。
    ///   - fieldFocus: ⌘A / ⌘V の前に、移動先シートの入力欄がフォーカスを持つまで待つ。nil なら待たずに送る。
    ///   - submitGate: Return の前に移動先シートの入力欄と候補の選択を確かめる。nil なら確かめずに Return を送る。
    ///   - clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        pasteboard: any PasteboardAccessing,
        keyboard: any KeyStrokePosting,
        sheetDetector: any GoToSheetDetecting,
        targetGuard: any InjectionTargetGuarding,
        fieldFocus: GoToFieldFocusWait? = nil,
        submitGate: GoToSheetSubmitGate? = nil,
        hooks: PathInjectionHooks = .none,
        timing: PathInjectionTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.pasteboard = pasteboard
        self.keyboard = keyboard
        self.sheetDetector = sheetDetector
        self.targetGuard = targetGuard
        self.fieldFocus = fieldFocus
        self.submitGate = submitGate
        self.hooks = hooks
        self.timing = timing
        self.clock = clock
    }

    /// NSOpenPanel を path へ移動させる。
    /// - Throws: 失敗時は `InjectionError`、キャンセル時は `CancellationError`。
    ///   OS 側の操作の失敗は、ユーザーに見せる文言が合うよう失敗したステップの `timeout(step:)` に寄せる。
    public func run(path: String, autoConfirm: Bool) async throws {
        await gate.enter()
        defer { gate.leave() }
        try Task.checkCancellation()
        let timeline = ElapsedTimeline(clock: clock)

        let probe = try await makeProbe(on: timeline)
        await hooks.prepareForKeyEvents()
        try Task.checkCancellation()
        try await post(.goToFolder, failingAs: .waitSheet, on: timeline)
        Self.logStep("⌘⇧G を送りました", on: timeline)
        try await waitForSheet(probe, on: timeline)
        try Task.checkCancellation()
        Self.logStep("移動先シートが出ました", on: timeline)
        let controls = try await waitForFieldFocus(on: timeline)
        try Task.checkCancellation()

        // 入力欄がキーを受け取れるようになってから差し替えることで、⌘⇧G が効かない・入力欄にキーが届かない場合
        // （副方式へのフォールバック）にペーストボードへ触れずに済む
        let restoration = PasteboardRestoration(try replacePasteboard(with: path))
        do {
            try await pasteAndSubmit(path: path, controls: controls, restoration: restoration, autoConfirm: autoConfirm, on: timeline)
        } catch {
            try Self.restore(restoration)
            throw error
        }
        let isRestoredBeforeSubmit = restoration.isDone
        // Return の前に戻していれば書き込まず、その結果（戻せなかったこと）を伝える
        try Self.restore(restoration)
        if !isRestoredBeforeSubmit {
            Self.logStep("ペーストボードを戻しました", on: timeline)
        }
    }

    // MARK: - ステップ

    /// 基準の記録にもシート待ちと同じ上限を設ける。応答しないアプリで走査が終わらず、次の注入を待たせ続けないため。
    private func makeProbe(on timeline: ElapsedTimeline) async throws -> any GoToSheetProbe {
        let deadline = timeline.elapsed + timing.sheetWaitLimit
        do {
            return try await withScanCutoff(at: deadline, on: timeline) { cutoff in
                try await sheetDetector.makeProbe(cutoff: cutoff)
            }
        } catch {
            throw Self.injectionError(from: error, failingAs: .waitSheet)
        }
    }

    /// 最初の確認は間隔 1 回分待ってから行う。⌘⇧G の直後にシートが出ていることはなく、AX の往復が無駄になるため。
    /// 走査は期限で打ち切るため、期限の時点から始める確認は行わない。
    private func waitForSheet(_ probe: any GoToSheetProbe, on timeline: ElapsedTimeline) async throws {
        let deadline = timeline.elapsed + timing.sheetWaitLimit
        var nextCheck = timeline.elapsed + timing.sheetPollInterval
        while nextCheck < deadline {
            try await timeline.sleep(untilElapsed: nextCheck)
            if try await isSheetShown(probe, cutoffAt: deadline, on: timeline) {
                return
            }
            nextCheck = timeline.elapsed + timing.sheetPollInterval
        }
        throw InjectionError.timeout(step: .waitSheet)
    }

    private func isSheetShown(
        _ probe: any GoToSheetProbe,
        cutoffAt deadline: Duration,
        on timeline: ElapsedTimeline
    ) async throws -> Bool {
        do {
            return try await withScanCutoff(at: deadline, on: timeline) { cutoff in
                try await probe.isSheetShown(cutoff: cutoff)
            }
        } catch {
            throw Self.injectionError(from: error, failingAs: .waitSheet)
        }
    }

    /// シートが AX に現れた直後は入力欄がまだキー入力の受け先になっておらず、⌘A / ⌘V が入力欄に届かないことがある
    /// （Issue #74。macOS 26.6.2 の QA で、シートの検知の 1ms 後に送った ⌘A / ⌘V が効かなかった）。
    /// フォーカスが来なければ、貼り付けても入力欄に入らず確定前の確認で副方式へ回るだけなので、待ち（約 350ms）を省いて副方式に任せる。
    /// AX でフォーカスを与えても、シートがキーウィンドウでなければキー入力は届かないため、ここでは与えない。
    /// - Returns: 見つけた入力欄（確定前の確認で探し直さずに使う）。
    private func waitForFieldFocus(on timeline: ElapsedTimeline) async throws -> GoToFieldControls? {
        guard let fieldFocus else { return nil }
        let result = try await fieldFocus.waitUntilFocused()
        Self.logStep("入力欄のフォーカスを待ちました（\(result.focus.rawValue)）", on: timeline)
        switch result.focus {
        case .focused, .unavailable:
            return result.controls
        case .notFocused, .fieldGone:
            // シートごとパネルが閉じていれば、貼り付けの失敗ではなくパネルが消えたことを伝える
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            Log.warning("移動先シートの入力欄がキー入力を受け取れる状態にならないため、貼り付けずに副方式へ切り替えます（\(result.focus.rawValue)）")
            throw InjectionError.timeout(step: .waitPaste)
        }
    }

    private func replacePasteboard(with path: String) throws -> PasteboardSwap {
        do {
            return try PasteboardSwap(replacingContentsOf: pasteboard, with: path)
        } catch {
            throw InjectionError.timeout(step: .waitPaste)
        }
    }

    /// ステップ 5〜9。ペーストボードは、貼り付けを確かめられたら Return の前にここで戻し、それ以外は呼び出し元が戻す。
    private func pasteAndSubmit(
        path: String,
        controls: GoToFieldControls?,
        restoration: PasteboardRestoration,
        autoConfirm: Bool,
        on timeline: ElapsedTimeline
    ) async throws {
        let heldPathBeforePaste = await submitGate?.fieldMatches(path: path, controls: controls)
        try await post(.selectAll, failingAs: .waitPaste, on: timeline)
        try await post(.paste, failingAs: .waitPaste, on: timeline)
        Self.logStep("⌘A と ⌘V を送りました", on: timeline)
        try await timeline.sleep(untilElapsed: timeline.elapsed + timing.pasteSettleDelay)
        let readiness = try await ensureReadyToSubmit(path: path, controls: controls, on: timeline)
        // 貼り付けで入力欄が別の値から移動先に変わったなら、⌘V は処理済みでペーストボードの役目は終わっている。
        // 最初から移動先が入っていた（前回と同じ移動先）場合は、⌘V が処理されたか分からないため Return の後まで戻さない
        if heldPathBeforePaste == false, readiness?.confirmsFieldValue == true {
            restoration.perform()
            Self.logStep("貼り付けたパスが入力欄に入ったため、Return の前にペーストボードを戻しました", on: timeline)
        }
        try await ensureFieldStillFocused(controls, on: timeline)
        try await post(.returnKey, failingAs: .waitPaste, on: timeline)
        Self.logStep("Return を送りました", on: timeline)

        let submittedAt = timeline.elapsed
        try await hooks.didSubmitGoToSheet(autoConfirm)
        guard !restoration.isDone else { return }
        try await timeline.sleep(untilElapsed: submittedAt + timing.restoreDelay)
    }

    /// 入力欄の値が移動先でないまま Return を送ると、移動先シートに残っていた前回の場所へ移動してしまう（Issue #74）。
    /// その場合は Return を送らずに `timeout(.waitPaste)` を投げ、AX で値を直接セットする副方式に任せる。
    /// - Returns: 確定前の確認の判定。確かめない（submitGate が無い）場合は nil。
    private func ensureReadyToSubmit(
        path: String,
        controls: GoToFieldControls?,
        on timeline: ElapsedTimeline
    ) async throws -> GoToSheetReadiness? {
        guard let submitGate else { return nil }
        let readiness = try await submitGate.waitUntilReady(path: path, controls: controls)
        Self.logStep("確定前の確認を終えました（\(readiness.rawValue)）", on: timeline)
        guard readiness != .fieldMismatch else {
            Log.warning("移動先シートの入力欄が貼り付けたパスになっていないため、Return を送らずに副方式へ切り替えます")
            throw InjectionError.timeout(step: .waitPaste)
        }
        return readiness
    }

    /// 確定前の確認は、フォーカスを待つときに見つけた入力欄を読む。待つ間に別のシートへフォーカスが移っていると、
    /// Return は確かめた入力欄ではなくそのシートに届いてしまうため、送る直前に確かめた入力欄がまだフォーカスを持つかを確かめる。
    /// 持たなければ（入力欄が消えた場合も）Return を送らずに `timeout(.waitPaste)` を投げ、フォーカスを待ってから確定する副方式に任せる。
    /// 入力欄を見つけていない・フォーカスを読めない場合は、確かめられないため従来どおり送る。
    private func ensureFieldStillFocused(_ controls: GoToFieldControls?, on timeline: ElapsedTimeline) async throws {
        guard let fieldFocus, let controls else { return }
        let focus = try await fieldFocus.currentFocus(of: controls)
        guard focus == .notFocused || focus == .fieldGone else { return }
        // シートごとパネルが閉じていれば、貼り付けの失敗ではなくパネルが消えたことを伝える
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        Log.warning("Return の前に移動先シートの入力欄がフォーカスを失ったため、Return を送らずに副方式へ切り替えます（\(focus.rawValue)）")
        throw InjectionError.timeout(step: .waitPaste)
    }

    /// キーはその時点のキーウィンドウに届くため、送る直前に注入先がまだ有効かを確かめる。
    /// 注入中に別のアプリへ切り替わると、⌘A / ⌘V / Return がそのアプリに届いてしまう（チャットアプリでの送信など）。
    private func post(
        _ keyStroke: InjectionKeyStroke,
        failingAs step: InjectionStep,
        on timeline: ElapsedTimeline
    ) async throws {
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        do {
            try keyboard.post(keyStroke)
        } catch {
            throw Self.injectionError(from: error, failingAs: step)
        }
    }

    /// 手順の進み具合を、注入の開始からの経過時間付きで debug ログに残す。
    private static func logStep(_ step: String, on timeline: ElapsedTimeline) {
        Log.debug("主方式: \(step)（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
    }

    /// 戻せなかったことは、元の注入の結果（成功・他のエラー）より優先して伝える。ユーザーのクリップボードが失われているため。
    /// 他者の書き込みを優先して戻さなかった場合と、機密の内容を戻さずに空にした場合は、意図どおりなので失敗にしない。
    private static func restore(_ restoration: PasteboardRestoration) throws {
        switch restoration.perform() {
        case .failed:
            throw InjectionError.pasteboardRestoreFailed
        case .clearedBecauseConcealed:
            Log.info("クリップボードの内容が機密（パスワード等）だったため、元に戻さずに空にしました")
        case .restored, .skippedBecauseReplacedByOthers, .alreadyRestored:
            break
        }
    }

    /// OS 側の操作の失敗を InjectionError に寄せる。InjectionError とキャンセルはそのまま通す。
    private static func injectionError(from error: any Error, failingAs step: InjectionStep) -> any Error {
        if error is InjectionError || error is CancellationError {
            return error
        }
        // 走査を打ち切った理由がキャンセルなら、タイムアウトではなくキャンセルとして伝える
        if error is ScanCutoff.Reached, Task.isCancelled {
            return CancellationError()
        }
        return InjectionError.timeout(step: step)
    }
}
