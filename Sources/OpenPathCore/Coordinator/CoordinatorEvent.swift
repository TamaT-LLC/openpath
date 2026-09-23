/// AppCoordinator へ外部（PanelWatcher / PaletteWindow / ホットキー）から届くイベント。
/// 注入の完了（成功・失敗・タイムアウト）は古い注入の結果を取り違えないよう、Coordinator 内部で扱う。
public enum CoordinatorEvent: Equatable, Sendable {
    /// NSOpenPanel が現れた。
    case panelAppeared(PanelContext)
    /// 追跡中のパネルが消えた（キャンセル・確定・アプリ終了等）。
    case panelGone
    /// 追跡中のパネルの情報が変わった。選択モードを推定し直した結果フォルダのみかどうかが変わった（DSN-001 §2.3）か、
    /// パネルが動いた（走査したときに分かった分だけ）。
    case panelContextChanged(PanelContext)
    /// パレットで候補を確定した。openImmediately は Cmd+Enter（設定に関わらず自動確定）。
    case confirm(path: String, openImmediately: Bool)
    /// パレットで Esc が押された。
    case escape
    /// 再表示用のグローバルホットキーが押された。
    case hotkey
}
