// AppCoordinator が各モジュールを扱うためのプロトコル群。
// AppKit / AX に依存する実体（PaletteWindow, PanelInjector, HistoryStore）は他モジュールで実装し、
// Core からはこのプロトコル越しにのみ扱う。UI と同じスレッドで呼ぶため MainActor に隔離する。

/// パレット（PaletteWindow）の表示制御。
@MainActor
public protocol PaletteDisplaying {
    /// パネルに重ねてパレットを表示する。
    func show(context: PanelContext)
    /// 表示中のパネルの情報（選択モードの推定・位置）が変わった。候補の絞り込みと位置を合わせる。
    func update(context: PanelContext)
    func hide()
    /// 注入中はロックし、キー入力を捨てる（DSN-001 §5）。
    func setLocked(_ isLocked: Bool)
    /// フッターに状態を表示する（例: 「パネルへ移動中…」）。
    func showStatus(_ message: String)
    /// フッターにエラーを赤字で表示する。
    func showError(_ message: String)
}

/// NSOpenPanel へのパス注入（PanelInjector）。
@MainActor
public protocol PathInjecting {
    /// パネルを path へ移動させ、autoConfirm なら「開く」も押す。
    /// 失敗時は InjectionError を投げる。キャンセルされたら速やかに戻り、ペーストボードは復元すること。
    func inject(path: String, autoConfirm: Bool) async throws
}

/// 確定したパスの履歴記録（HistoryStore）。
@MainActor
public protocol HistoryRecording {
    func record(path: String)
}
