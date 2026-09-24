/// 「試してみる」のダイアログ（osascript）を前面に出す（Issue #72）。
///
/// `timing.pollInterval` ごとに osascript の状態を確かめ、`TrialPanelActivation` の判定に従って前面に出す要求を送る。
/// 状態の確かめ方と要求の送り方は OpenPathMac が渡す（`NSRunningApplication`）。
@MainActor
public struct TrialPanelActivator {
    /// osascript の状態を確かめる
    public typealias Observe = @MainActor () -> TrialPanelProcessState
    /// 前面に出す要求を送る。前面に出たかは、次に確かめた状態で判断する
    public typealias Activate = @MainActor () -> Void

    private let timing: TrialPanelActivationTiming
    private let clock: any Clock<Duration>
    private let observe: Observe
    private let activate: Activate

    /// - Parameters:
    ///   - timing: 待ち方
    ///   - clock: 待機に使う。テストでは実時間を待たない Clock を渡す
    ///   - observe: osascript の状態を確かめる
    ///   - activate: 前面に出す要求を送る
    public init(
        timing: TrialPanelActivationTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock(),
        observe: @escaping Observe,
        activate: @escaping Activate
    ) {
        self.timing = timing
        self.clock = clock
        self.observe = observe
        self.activate = activate
    }

    /// 前面に出るか、ダイアログが閉じられるか、期限まで待つ。
    /// - Returns: 結果。キャンセルされたら nil
    public func run() async -> TrialPanelActivationOutcome? {
        let timeline = ElapsedTimeline(clock: clock)
        var activation = TrialPanelActivation(timing: timing)
        var checks = 0
        while true {
            switch activation.next(observing: observe(), at: timeline.elapsed) {
            case .finish(let outcome):
                return outcome
            case .activate:
                activate()
            case .wait:
                break
            }
            checks += 1
            do {
                // 確かめる時刻を起点からの倍数にそろえ、処理にかかった時間で間隔がずれないようにする
                try await timeline.sleep(untilElapsed: timing.pollInterval * checks)
            } catch {
                return nil
            }
        }
    }
}
