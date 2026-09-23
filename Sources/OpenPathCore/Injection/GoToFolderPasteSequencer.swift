/// パス注入の主方式（⌘⇧G + ペースト）の手順を実行する（DSN-001 §3.1、ARCH-001 §7）。
///
/// 手順（括弧内は DSN-001 §3.1 のステップ番号）:
/// 1. 移動先シートの判定基準を記録する（`GoToSheetDetecting.makeProbe`）
/// 2. `hooks.prepareForKeyEvents` でキー入力を NSOpenPanel へ向ける
/// 3. ⌘⇧G を送り（3）、最大 600ms・50ms 間隔でシートの出現を待つ（4）
/// 4. ペーストボードを退避してパスを書き込み（1, 2）、⌘A → ⌘V（5）
/// 5. 100ms 待って（6）Return を送る（7）
/// 6. `hooks.didSubmitGoToSheet`（8: auto_confirm の差し込み口）
/// 7. Return から 200ms 後にペーストボードを戻す（9）
///
/// - ペーストボードは差し替えた後なら、成功・失敗・キャンセルのどの経路でも戻す。
///   失敗・キャンセル時は 200ms を待たずにすぐ戻す。
/// - キャンセルには各ステップの間と待機中に応じ、以降のキー操作は送らない。
///   AX の呼び出しはキャンセルできないため、呼び出し中なら完了を待ってから応じる。
/// - 前の注入が後始末を終えるまで、次の注入は始めない（`InjectionSerialGate`）。
@MainActor
public final class GoToFolderPasteSequencer {
    private let pasteboard: any PasteboardAccessing
    private let keyboard: any KeyStrokePosting
    private let sheetDetector: any GoToSheetDetecting
    private let hooks: PathInjectionHooks
    private let timing: PathInjectionTiming
    private let clock: any Clock<Duration>
    private let gate = InjectionSerialGate()

    /// - Parameter clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        pasteboard: any PasteboardAccessing,
        keyboard: any KeyStrokePosting,
        sheetDetector: any GoToSheetDetecting,
        hooks: PathInjectionHooks = .none,
        timing: PathInjectionTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.pasteboard = pasteboard
        self.keyboard = keyboard
        self.sheetDetector = sheetDetector
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

        let probe = try await makeProbe()
        await hooks.prepareForKeyEvents()
        try Task.checkCancellation()
        try post(.goToFolder, failingAs: .waitSheet)
        try await waitForSheet(probe, on: timeline)
        try Task.checkCancellation()

        // シートが出てから差し替えることで、⌘⇧G が効かない場合（副方式へのフォールバック）にペーストボードへ触れずに済む
        let swap = try replacePasteboard(with: path)
        defer { swap.restore() }
        try post(.selectAll, failingAs: .waitPaste)
        try post(.paste, failingAs: .waitPaste)
        try await timeline.sleep(untilElapsed: timeline.elapsed + timing.pasteSettleDelay)
        try post(.returnKey, failingAs: .waitPaste)

        let submittedAt = timeline.elapsed
        try await hooks.didSubmitGoToSheet(autoConfirm)
        try await timeline.sleep(untilElapsed: submittedAt + timing.restoreDelay)
    }

    // MARK: - ステップ

    private func makeProbe() async throws -> any GoToSheetProbe {
        do {
            return try await sheetDetector.makeProbe()
        } catch {
            throw Self.injectionError(from: error, failingAs: .waitSheet)
        }
    }

    /// 最初の確認は間隔 1 回分待ってから行う。⌘⇧G の直後にシートが出ていることはなく、AX の往復が無駄になるため。
    private func waitForSheet(_ probe: any GoToSheetProbe, on timeline: ElapsedTimeline) async throws {
        let deadline = timeline.elapsed + timing.sheetWaitLimit
        var nextCheck = timeline.elapsed + timing.sheetPollInterval
        while true {
            try await timeline.sleep(untilElapsed: min(nextCheck, deadline))
            if try await isSheetShown(probe) {
                return
            }
            let now = timeline.elapsed
            guard now < deadline else {
                throw InjectionError.timeout(step: .waitSheet)
            }
            nextCheck = now + timing.sheetPollInterval
        }
    }

    private func isSheetShown(_ probe: any GoToSheetProbe) async throws -> Bool {
        do {
            return try await probe.isSheetShown()
        } catch {
            throw Self.injectionError(from: error, failingAs: .waitSheet)
        }
    }

    private func replacePasteboard(with path: String) throws -> PasteboardSwap {
        do {
            return try PasteboardSwap(replacingContentsOf: pasteboard, with: path)
        } catch {
            throw InjectionError.timeout(step: .waitPaste)
        }
    }

    private func post(_ keyStroke: InjectionKeyStroke, failingAs step: InjectionStep) throws {
        do {
            try keyboard.post(keyStroke)
        } catch {
            throw Self.injectionError(from: error, failingAs: step)
        }
    }

    /// OS 側の操作の失敗を InjectionError に寄せる。InjectionError とキャンセルはそのまま通す。
    private static func injectionError(from error: any Error, failingAs step: InjectionStep) -> any Error {
        if error is InjectionError || error is CancellationError {
            return error
        }
        return InjectionError.timeout(step: step)
    }
}
