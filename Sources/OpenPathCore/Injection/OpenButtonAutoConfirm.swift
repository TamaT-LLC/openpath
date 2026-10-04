/// auto_confirm または Cmd+Enter のとき、移動後にパネルの「開く」ボタンを押す（DSN-001 §3.1 ステップ 8、FR-INJECT-03）。
///
/// 主方式では Return（移動先シートの確定）の後、副方式では「移動」の押下・Return の後に、移動先シートが閉じたのを確かめてから呼ぶ
/// （`PathInjectionHooks.didSubmitGoToSheet`、Issue #95）。
/// 「開く」の押下でパネルが閉じるのは正常なので、押した後にパネルが消えたことは成功として扱い、`.panelGone` は投げない
/// （AppCoordinator は自動確定中のパネルの消滅で注入を止めず、この結果を待って履歴に残す）。
///
/// 「開く」は、移動先シートが閉じるまで押せない状態（AXEnabled が false）のままで、閉じてから押せる状態に戻る
/// （macOS 27 の自プロセスのパネルで、Return から約 410ms。Issue #89）。そのため、見つけたボタンが押せる状態になるまで
/// 間隔を空けて確かめ直し、見つからなければ探し直す（パネルの移動直後の作り直しに備える）。待つのは探す時間も含めた
/// 累積の上限（`PanelControlTiming.openButtonReadyLimit`）までで、全体の最悪の時間は以前と変わらない。
/// どのように特定したか（表題・既定ボタン）と待った時間を debug ログに残す（ボタンの表題は出さない）。
@MainActor
public final class OpenButtonAutoConfirm {
    /// 確定ボタンが押せる状態か。
    private enum ButtonState {
        /// 押せる（押せるか分からない場合も、従来どおり押す）
        case pressable
        /// 押せない（AXEnabled が false）
        case disabled
        /// 消えた（作り直された、パネルが閉じた）
        case gone
    }

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
        { [self] autoConfirm, elapsedSinceSubmit in
            try await confirm(autoConfirm: autoConfirm, elapsedSinceSubmit: elapsedSinceSubmit)
        }
    }

    /// autoConfirm なら、確定から 300ms 経つまで待ってから「開く」を探し、押せる状態になってから押す。
    /// autoConfirm でなければ何もしない（既定は自動で開かない）。
    /// - Parameter elapsedSinceSubmit: 確定（Return・「移動」の押下）から呼ばれるまでに経った時間（移動先シートが閉じるのを確かめた時間）。
    ///   その分は待たない。閉じるのを確かめた後に 300ms を重ねると、「開く」の押下が閉じるまでの時間（約 400ms）だけ遅れるため（Issue #95）。
    /// - Throws: 期限までにボタンが見つからなければ `InjectionError.axError(failure)`、探すのが期限内に終わらない・
    ///   押せる状態にならなければ `.axError(cannotComplete)`、押せなければ `.axError`、
    ///   押す前に注入先が無効になっていれば `.panelGone` / `.targetNotFrontmost`、キャンセル時は `CancellationError`。
    public func confirm(autoConfirm: Bool, elapsedSinceSubmit: Duration = .zero) async throws {
        guard autoConfirm else { return }
        let timeline = ElapsedTimeline(clock: clock)
        // 移動先シートが閉じ、パネルの移動が反映されてから押す
        try await timeline.sleep(untilElapsed: max(.zero, timing.openButtonDelay - elapsedSinceSubmit))

        let button = try await waitForPressableButton(on: timeline)
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        // 押した後はキャンセルを確かめない。「開く」は押された後なので、結果を成功として返す
        try await PanelControlOperation.activate(button, by: .press)
        Log.debug("auto_confirm: 確定ボタンを押しました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
    }

    /// 確定ボタンを探し、押せる状態になるまで待つ。見つからない・消えたら探し直す（Issue #89）。
    /// 走査は期限で打ち切るため、期限の時点から始める確認は行わない（最後の確認は期限の 1 間隔前まで）。
    private func waitForPressableButton(on timeline: ElapsedTimeline) async throws -> any PanelElementOperating {
        let startedAt = timeline.elapsed
        let deadline = startedAt + timing.openButtonReadyLimit
        var location: OpenButtonLocation?
        var lookupCount = 0
        var disabledCheckCount = 0
        while true {
            if location == nil {
                do {
                    location = try await lookUp(until: deadline, on: timeline)
                } catch InjectionError.axError(code: InjectionAXErrorCode.cannotComplete) where lookupCount > 0 {
                    // 探し終えた走査で見つからず、探し直しの途中で期限を迎えた。探すのが遅いのではなく、見つからなかった
                    throw Self.readinessError(isFound: false, lookupCount: lookupCount, on: timeline)
                }
                lookupCount += 1
                if let location {
                    Self.logIdentification(location.identification, on: timeline)
                }
            }
            if let current = location {
                switch try await state(of: current.button) {
                case .pressable:
                    if disabledCheckCount > 0 {
                        let waited = InjectionLogFormat.milliseconds(timeline.elapsed - startedAt)
                        Log.debug("auto_confirm: 確定ボタンが押せる状態になりました（探し始めてから \(waited)、押せない状態を確かめた回数 \(disabledCheckCount) 回）")
                    }
                    return current.button
                case .disabled:
                    if disabledCheckCount == 0 {
                        Log.debug("auto_confirm: 確定ボタンが押せない状態（AXEnabled が false）のため、押せる状態になるまで待ちます")
                    }
                    disabledCheckCount += 1
                case .gone:
                    Log.debug("auto_confirm: 確定ボタンが消えたため、探し直します")
                    location = nil
                }
            }
            let nextCheck = timeline.elapsed + timing.openButtonPollInterval
            guard nextCheck < deadline else {
                throw Self.readinessError(isFound: location != nil, lookupCount: lookupCount, on: timeline)
            }
            try await timeline.sleep(untilElapsed: nextCheck)
        }
    }

    /// 走査は累積の期限で打ち切る。期限で打ち切ったら `axError(cannotComplete)`。
    private func lookUp(until deadline: Duration, on timeline: ElapsedTimeline) async throws -> OpenButtonLocation? {
        try await PanelControlOperation.lookUp(
            within: deadline - timeline.elapsed,
            on: timeline,
            failingAs: .axError(code: InjectionAXErrorCode.cannotComplete)
        ) { cutoff in
            try await locator.locateOpenButton(cutoff: cutoff)
        }
    }

    /// 押せる状態を読めない（要素が消えた以外の AX の失敗、属性が無い）場合は、確かめられないため従来どおり押す。
    private func state(of button: any PanelElementOperating) async throws -> ButtonState {
        do {
            return try await button.isEnabled() == false ? .disabled : .pressable
        } catch {
            try Task.checkCancellation()
            if error as? InjectionError == .panelGone {
                return .gone
            }
            Log.debug("auto_confirm: 確定ボタンが押せる状態かを読めませんでした（\(error)）")
            return .pressable
        }
    }

    private static func logIdentification(_ identification: OpenButtonIdentification, on timeline: ElapsedTimeline) {
        let means = switch identification {
        case .title: "表題"
        case .defaultButton: "既定ボタン（AXDefaultButton）"
        }
        Log.debug("auto_confirm: 確定ボタンを\(means)で特定しました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
    }

    /// 見つからないままなら「見つからない」（failure）、見つけたが押せないままなら「期限内に終わらない」（cannotComplete）。
    private static func readinessError(isFound: Bool, lookupCount: Int, on timeline: ElapsedTimeline) -> InjectionError {
        let elapsed = InjectionLogFormat.milliseconds(timeline.elapsed)
        guard isFound else {
            Log.debug("auto_confirm: 確定ボタンが見つかりません（探した回数 \(lookupCount) 回、+\(elapsed)）")
            return .axError(code: InjectionAXErrorCode.failure)
        }
        Log.debug("auto_confirm: 確定ボタンが期限までに押せる状態になりませんでした（+\(elapsed)）")
        return .axError(code: InjectionAXErrorCode.cannotComplete)
    }
}
