/// auto_confirm または Cmd+Enter のとき、移動後にパネルの「開く」ボタンを押す（DSN-001 §3.1 ステップ 8、FR-INJECT-03）。
///
/// 主方式では Return（移動先シートの確定）の後、副方式では「移動」の押下の後に呼ぶ（`PathInjectionHooks.didSubmitGoToSheet`）。
/// 「開く」の押下でパネルが閉じるのは正常なので、押した後にパネルが消えたことは成功として扱い、`.panelGone` は投げない
/// （AppCoordinator は自動確定中のパネルの消滅で注入を止めず、この結果を待って履歴に残す）。
@MainActor
public final class OpenButtonAutoConfirm {
    private let locator: any OpenButtonLocating
    private let targetGuard: any InjectionTargetGuarding
    private let timing: PanelControlTiming
    private let clock: any Clock<Duration>

    /// - Parameter clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any OpenButtonLocating,
        targetGuard: any InjectionTargetGuarding,
        timing: PanelControlTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.targetGuard = targetGuard
        self.timing = timing
        self.clock = clock
    }

    /// `PathInjectionHooks.didSubmitGoToSheet` として渡す形。
    public var hook: PathInjectionHooks.DidSubmitGoToSheet {
        { [self] autoConfirm in
            try await confirm(autoConfirm: autoConfirm)
        }
    }

    /// autoConfirm なら 300ms 待ってから「開く」を押す。autoConfirm でなければ何もしない（既定は自動で開かない）。
    /// - Throws: ボタンが見つからない・押せない場合は `InjectionError.axError`、押す前に注入先が無効になっていれば
    ///   `.panelGone` / `.targetNotFrontmost`、キャンセル時は `CancellationError`。
    public func confirm(autoConfirm: Bool) async throws {
        guard autoConfirm else { return }
        let timeline = ElapsedTimeline(clock: clock)
        // 移動先シートが閉じ、パネルの移動が反映されてから押す
        try await timeline.sleep(untilElapsed: timing.openButtonDelay)

        let foundButton = try await PanelControlOperation.lookUp(
            within: timing.controlLookupLimit,
            on: timeline,
            failingAs: .axError(code: InjectionAXErrorCode.cannotComplete)
        ) { cutoff in
            try await locator.locateOpenButton(cutoff: cutoff)
        }
        guard let button = foundButton else {
            throw InjectionError.axError(code: InjectionAXErrorCode.failure)
        }
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        // 押した後はキャンセルを確かめない。「開く」は押された後なので、結果を成功として返す
        try await PanelControlOperation.activate(button, by: .press)
    }
}
