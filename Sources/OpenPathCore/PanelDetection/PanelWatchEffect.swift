/// `PanelWatchPolicy` が入力に応じて求める副作用。PanelWatchEngine が並び順どおりに実行する。
public enum PanelWatchEffect: Equatable, Sendable {
    /// 既存の観測を外してから、processID のアプリに AXObserver を張る。
    case attach(processID: Int32)
    /// AXObserver を外す。
    case detach
    /// 補助ポーリングを始める。
    case startPolling
    /// 補助ポーリングを止める。
    case stopPolling
    /// パネルを走査する。結果は `PanelWatchInput.scanCompleted` で返す。
    case scan(PanelScanRequest)
    /// AppCoordinator へイベントを送る（`panelAppeared` / `panelGone` のみ）。
    case send(CoordinatorEvent)
}
