/// パス注入の副方式（AX 直接セット、DSN-001 §3.2）。
///
/// 主方式が移動先シートを見つけられなかった（`timeout(.waitSheet)`）か、シートは出たが貼り付けの操作に失敗した
/// （`timeout(.waitPaste)`）ときに使う。移動先シートの入力欄を AX で探し直し、値を直接セットして「移動」/「Go」を押す
/// （無ければ入力欄を確定する）。その後はステップ 8（auto_confirm）へ進む。
///
/// - ペーストボードもキー操作も使わない。
/// - 入力欄が見つからなければ、主方式の失敗をそのまま投げる。パレットの文言を主方式の失敗理由（⌘⇧G が開かない等）にするため。
/// - 値のセットと押下の直前ごとに注入先を確かめる。
@MainActor
public final class GoToFieldDirectEntry {
    private let locator: any GoToFieldLocating
    private let targetGuard: any InjectionTargetGuarding
    private let didSubmit: PathInjectionHooks.DidSubmitGoToSheet
    private let timing: PanelControlTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - didSubmit: 「移動」を押した後に呼ぶ（主方式の `PathInjectionHooks.didSubmitGoToSheet` と同じもの）。
    ///   - clock: 走査の期限の計測に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        targetGuard: any InjectionTargetGuarding,
        didSubmit: @escaping PathInjectionHooks.DidSubmitGoToSheet = { _ in },
        timing: PanelControlTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.targetGuard = targetGuard
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
            throw primaryError
        }

        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        try await PanelControlOperation.setValue(path, on: controls.field)
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        if let goButton = controls.goButton {
            try await PanelControlOperation.activate(goButton, by: .press)
        } else {
            try await PanelControlOperation.activate(controls.field, by: .confirm)
        }
        try await didSubmit(autoConfirm)
    }
}
