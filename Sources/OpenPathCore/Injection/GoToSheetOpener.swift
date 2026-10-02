/// キー操作の送出（主方式の各ステップで共通）。送る直前に注入先を確かめ、OS 側の失敗をステップの失敗に寄せる。
@MainActor
struct InjectionKeySender {
    let keyboard: any KeyStrokePosting
    let targetGuard: any InjectionTargetGuarding

    /// 送る直前に注入先がまだ有効かを確かめる。注入中に別のアプリへ切り替わると、システム経由のキーはそのアプリに届いてしまう
    /// （チャットアプリでの送信など）。注入先のプロセスへ送るキーは別のアプリには届かないが、注入先の別のウィンドウに届くため同じく確かめる。
    /// 送り先を決める（AX の読み取りを伴う）準備は確認の前に済ませ、確認とキャンセルの確認の後は待ちを挟まずに送る。
    func post(
        _ keyStroke: InjectionKeyStroke,
        via route: InjectionKeyRoute,
        failingAs step: InjectionStep,
        on timeline: ElapsedTimeline
    ) async throws {
        let prepared = try await prepare(keyStroke, via: route, failingAs: step)
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        try Task.checkCancellation()
        prepared.post()
    }

    /// 送る準備（送り先の決定とキーイベントの組み立て）。失敗はステップの失敗に寄せる。
    func prepare(
        _ keyStroke: InjectionKeyStroke,
        via route: InjectionKeyRoute,
        failingAs step: InjectionStep
    ) async throws -> PreparedKeyStroke {
        try Task.checkCancellation()
        do {
            return try await keyboard.prepare(keyStroke, via: route)
        } catch {
            throw Self.injectionError(from: error, failingAs: step)
        }
    }

    /// OS 側の操作の失敗を InjectionError に寄せる。InjectionError とキャンセルはそのまま通す。
    static func injectionError(from error: any Error, failingAs step: InjectionStep) -> any Error {
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

/// 移動先シートを開き、出現を待つ（DSN-001 §3.1 ステップ 3〜4）。段ごとにキーを送り、出なければ次の段へ進む。
///
/// 1. ① ⌘⇧G を注入先のプロセスへ送る（他アプリのグローバルホットキーに横取りされない）。シートの出現を 50ms 間隔で待つ。
///    代替（`GoToSheetFallback`）があれば最大 200ms、無ければ最大 600ms（`openThroughTargetProcess`）
/// 2. ② フォーカスがファイル一覧なら、/ をシステム経由で送り、最大 300ms 待つ
/// 3. ③ ② を飛ばしたか、② でも出なければ、⌘⇧G をシステム経由で送り、最大 500ms 待つ（#107 より前の送り方。Issue #29）
/// 4. どの段でも出なければ `timeout(.waitSheet)` を投げる（副方式へ）
///
/// ① で出なかった注入先は `GoToSheetRouteMemory` に覚え、次の注入では ① を飛ばして ② から始める。
/// 覚えた注入先で ②・③ でも出なければ忘れる。キーを送る直前ごとの注入先の確認とキャンセルの確認は、どの段でも行う（`InjectionKeySender`）。
@MainActor
struct GoToSheetOpener {
    let sender: InjectionKeySender
    let fallback: GoToSheetFallback?
    let timing: PathInjectionTiming

    /// 移動先シートを開く。
    /// - Parameter willSendThroughSystemRoute: ②・③ のキーを送る前に呼ぶ。呼び出し側は、シートが出ずに副方式へ回る場合も含めて、
    ///   以降のキーをシステム経由で送る（注入先のプロセスへ送ったキーが届かなかったとみなす）。
    /// - Throws: どの段でもシートが出なければ `timeout(.waitSheet)`。注入先が無効になれば `.targetNotFrontmost` / `.panelGone`、
    ///   キーを送れない・判定に失敗したら `timeout(.waitSheet)`、キャンセル時は `CancellationError`。
    func open(_ probe: any GoToSheetProbe, on timeline: ElapsedTimeline, willSendThroughSystemRoute: () -> Void) async throws {
        let target = fallback?.targetIdentity()
        let memory = fallback?.routeMemory
        let skipsTargetProcess = memory?.skipsTargetProcessRoute(for: target) ?? false
        if skipsTargetProcess {
            Log.info("この注入先では、前に ⌘⇧G を注入先のプロセスへ送っても移動先シートが出なかったため、システム経由で送ります")
        } else {
            if try await openThroughTargetProcess(probe, on: timeline) {
                return
            }
            guard fallback != nil else {
                throw InjectionError.timeout(step: .waitSheet)
            }
            memory?.recordTargetProcessRouteMissed(for: target)
        }
        willSendThroughSystemRoute()
        guard try await openThroughSystemRoute(probe, on: timeline) else {
            if skipsTargetProcess {
                memory?.forget(target)
                GoToFolderPasteSequencer.logStep("システム経由でもシートが出なかったため、次の注入は注入先のプロセスへの ⌘⇧G から試します", on: timeline)
            }
            throw InjectionError.timeout(step: .waitSheet)
        }
    }

    /// ① ⌘⇧G を注入先のプロセスへ送り、シートの出現を待つ。
    /// 代替が無ければ ② 以降へ進めないため、従来どおり `sheetWaitLimit` まで待つ。
    /// - Returns: 期限までにシートが出たか。
    private func openThroughTargetProcess(_ probe: any GoToSheetProbe, on timeline: ElapsedTimeline) async throws -> Bool {
        try await sender.post(.goToFolder, via: .targetProcess, failingAs: .waitSheet, on: timeline)
        GoToFolderPasteSequencer.logStep("⌘⇧G を注入先のプロセスへ送りました", on: timeline)
        let limit = fallback == nil ? timing.sheetWaitLimit : timing.targetProcessSheetWaitLimit
        return try await waitForSheet(probe, within: limit, on: timeline)
    }

    /// ② / と ③ ⌘⇧G をシステム経由で送り、シートの出現を待つ。フォーカスは ② の前に 1 回だけ読む。
    /// - Returns: 期限までにシートが出たか。
    private func openThroughSystemRoute(_ probe: any GoToSheetProbe, on timeline: ElapsedTimeline) async throws -> Bool {
        try Task.checkCancellation()
        let focus = try await focusedElement(reading: fallback?.focusReader, on: timeline)
        // / は他アプリのグローバルホットキーにならないため横取りされないが、入力欄にフォーカスがあると文字として入ってしまう
        if focus == .fileList {
            Log.info("/ をシステム経由で送り、移動先シートを開きます（フォーカス: \(focus.rawValue)）")
            if try await openThroughSystemRoute(sending: .slash, within: timing.slashSheetWaitLimit, probe, on: timeline) {
                return true
            }
            Log.info("/ でも移動先シートが出なかったため、⌘⇧G をシステム経由で送ります")
        } else {
            Log.info("⌘⇧G をシステム経由で送り、移動先シートを開きます（フォーカス: \(focus.rawValue)）")
        }
        Log.debug("主方式: システム経由の ⌘⇧G は、⌘⇧G をグローバルホットキーにしている他アプリに横取りされることがあります")
        return try await openThroughSystemRoute(sending: .goToFolder, within: timing.systemGoToSheetWaitLimit, probe, on: timeline)
    }

    private func openThroughSystemRoute(
        sending keyStroke: InjectionKeyStroke,
        within limit: Duration,
        _ probe: any GoToSheetProbe,
        on timeline: ElapsedTimeline
    ) async throws -> Bool {
        try await sender.post(keyStroke, via: .systemWide, failingAs: .waitSheet, on: timeline)
        GoToFolderPasteSequencer.logStep("\(keyStroke.logName) をシステム経由で送りました", on: timeline)
        return try await waitForSheet(probe, within: limit, on: timeline)
    }

    /// 最初の確認は間隔 1 回分待ってから行う。キーを送った直後にシートが出ていることはなく、AX の往復が無駄になるため。
    /// 走査は期限で打ち切るため、期限の時点から始める確認は行わない。
    /// - Returns: 期限までにシートが出たか。
    private func waitForSheet(_ probe: any GoToSheetProbe, within limit: Duration, on timeline: ElapsedTimeline) async throws -> Bool {
        let deadline = timeline.elapsed + limit
        var nextCheck = timeline.elapsed + timing.sheetPollInterval
        while nextCheck < deadline {
            try await timeline.sleep(untilElapsed: nextCheck)
            if try await isSheetShown(probe, cutoffAt: deadline, on: timeline) {
                GoToFolderPasteSequencer.logStep("移動先シートが出ました", on: timeline)
                return true
            }
            nextCheck = timeline.elapsed + timing.sheetPollInterval
        }
        return false
    }

    /// 走査が期限で打ち切られたら、期限までに出なかったものとして扱う（代替を試す）。
    /// 判定そのものの失敗（AX の失敗）は、従来どおり代替を試さずに `timeout(.waitSheet)` で副方式へ回す。
    private func isSheetShown(_ probe: any GoToSheetProbe, cutoffAt deadline: Duration, on timeline: ElapsedTimeline) async throws -> Bool {
        do {
            return try await withScanCutoff(at: deadline, on: timeline) { cutoff in
                try await probe.isSheetShown(cutoff: cutoff)
            }
        } catch is ScanCutoff.Reached where !Task.isCancelled {
            return false
        } catch {
            throw InjectionKeySender.injectionError(from: error, failingAs: .waitSheet)
        }
    }

    /// 読めなければ（失敗・期限切れ・読み取りの構成が無い）`.unavailable`。
    /// - Throws: キャンセル時は `CancellationError`。
    private func focusedElement(
        reading reader: (any InjectionFocusReading)?,
        on timeline: ElapsedTimeline
    ) async throws -> InjectionFocusedElement {
        guard let reader else { return .unavailable }
        do {
            return try await withScanCutoff(at: timeline.elapsed + GoToSheetFallback.focusReadLimit, on: timeline) { cutoff in
                try await reader.focusedElement(cutoff: cutoff)
            }
        } catch {
            try Task.checkCancellation()
            Log.debug("主方式: フォーカス中の要素を読めませんでした（\(type(of: error))）")
            return .unavailable
        }
    }
}
