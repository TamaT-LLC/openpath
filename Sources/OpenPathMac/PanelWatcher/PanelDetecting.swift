import ApplicationServices

import OpenPathCore

/// PanelWatcher が使うパネル判定（DSN-001 §2.2）。既定の実装は `OpenPanelDetector`。
///
/// メソッドはどちらも axQueue 上で同期的に呼ばれる。
public protocol PanelDetecting: Sendable {
    /// 観測中のアプリの `kAXWindowsAttribute` の各ウィンドウについて呼ばれ、NSOpenPanel ならそれを返す。
    ///
    /// - サンドボックスアプリや `beginSheetModal` のパネルはウィンドウの子要素（AXSheet）として現れるため、子も調べること。
    /// - 同じパネルには同じ `PanelContext.ID` を返すこと。id が変わると別のパネルとみなし、`panelGone` → `panelAppeared` を送る。
    /// - nil を返すと、追跡中のパネルは消えたとみなされる。AX の一時的な失敗では、直前の結果を返すこと。
    func detectPanel(in window: AXUIElement) -> DetectedPanel?

    /// 観測中のアプリで要素が破棄された（`kAXUIElementDestroyedNotification`）。判定のキャッシュを捨てるために使う。
    func elementDestroyed(_ element: AXUIElement)
}

/// 見つけた NSOpenPanel。
public struct DetectedPanel {
    /// パネルの要素（ダイアログのウィンドウ、またはシート）。PanelWatcher がこの要素にも破棄の通知を登録する。
    public let element: AXUIElement
    /// `frame` は AX の座標系（左上原点）で返すこと。NSScreen の座標系への変換は PanelWatcher（PanelScanner）が行う。
    public let context: PanelContext

    public init(element: AXUIElement, context: PanelContext) {
        self.element = element
        self.context = context
    }
}
