/// PanelWatchEngine が AX を扱うための窓口。AX / AppKit に依存する実体は OpenPathMac で実装する。
@MainActor
public protocol PanelWatchEnvironment: AnyObject {
    /// 既存の観測を外してから、processID のアプリの AX 通知（ウィンドウ生成・要素破棄・フォーカスウィンドウ変更）の購読を始める。
    /// 通知が届いたら `PanelWatchEngine.axNotificationDidArrive(processID:)` を呼ぶこと。
    func attach(processID: Int32)
    /// AX 通知の購読をやめる。
    func detach()
    /// processID のアプリのウィンドウを列挙し、NSOpenPanel と判定したものを返す。
    /// AX 呼び出しは MainActor をブロックしないよう axQueue で行うこと（DSN-001 §5）。
    func scanPanels(processID: Int32) async -> PanelScanOutcome
}
