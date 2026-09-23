import CoreGraphics

/// パレットのウィンドウ（OpenPathMac の PaletteWindow）の操作。
/// パレットの表示の手順を Core でテストするため、NSPanel を持つ実体とはこのプロトコル越しにつなぐ。
@MainActor
public protocol PaletteWindowControlling: AnyObject {
    /// 表示中の候補数。ウィンドウの高さの計算に使う。候補を差し替えても自動では追従しないため、差し替えのたびに設定する。
    var rowCount: Int { get set }
    /// NSOpenPanel の近くに表示し、キー入力を受け取れる状態にする。`panelFrame` は NSScreen 座標。
    func show(near panelFrame: CGRect)
    /// 隠す。キー入力はホストアプリのキーウィンドウ（NSOpenPanel）へ戻る。
    func hide()
    /// 表示したまま、キー入力をホストアプリのキーウィンドウへ返す（注入のキー操作の前）。
    func releaseKey()
    /// 表示中のパレットにキー入力を戻す（注入の失敗の表示後）。
    func reclaimKey()
}
