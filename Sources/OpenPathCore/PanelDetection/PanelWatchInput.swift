/// `PanelWatchPolicy` への入力。NSWorkspace・AXObserver・AppCoordinator・ポーリングで起きたことを表す。
public enum PanelWatchInput: Equatable, Sendable {
    /// 監視を始める。frontmost はその時点の最前面アプリ（取得できなければ nil）。
    case start(frontmost: ActiveApplication?)
    /// 監視をやめる（アクセシビリティ権限の取り消し、メニューバーでの無効化など）。
    case stop
    /// 最前面のアプリが切り替わった（`NSWorkspace.didActivateApplicationNotification`）。
    case applicationActivated(ActiveApplication)
    /// アプリが終了した（`NSWorkspace.didTerminateApplicationNotification`）。
    case applicationTerminated(processID: Int32)
    /// 設定 `disabled_apps` が変わった。観測中・最前面のアプリを判定し直す。
    case disabledAppsChanged
    /// AppCoordinator の状態が変わった（`AppCoordinator.onStateChange`）。
    case coordinatorStateChanged(CoordinatorState)
    /// AXObserver の通知（ウィンドウ生成・要素破棄・フォーカスウィンドウ変更）が届いた。
    case axNotificationReceived(processID: Int32)
    /// AXObserver を張れなかった（通知が届かない）。
    case axObservationFailed(processID: Int32)
    /// 補助ポーリングの周期が来た。
    case pollTick
    /// 依頼した走査が完了した。
    case scanCompleted(PanelScanResult)
}
