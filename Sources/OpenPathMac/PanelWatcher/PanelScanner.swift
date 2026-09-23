import ApplicationServices

import OpenPathCore

/// ウィンドウが NSOpenPanel かどうかを判定し、該当すれば PanelContext を返す（判定は #18 で実装する）。
///
/// - 観測中のアプリの `kAXWindowsAttribute` の各ウィンドウに対して、axQueue 上で同期的に呼ばれる。
/// - サンドボックスアプリや `beginSheetModal` のパネルはウィンドウの子要素（AXSheet）として現れるため、
///   シートの確認は判定関数の側で行う。
/// - 同じパネルには同じ `PanelContext.ID` を返すこと。id が変わると別のパネルとみなし、`panelGone` → `panelAppeared` を送る。
public typealias PanelDetector = @Sendable (AXUIElement) -> PanelContext?

/// 観測中のアプリのウィンドウを列挙してパネルを探す。AX のプロセス間呼び出しを伴うため axQueue で呼ぶこと。
enum PanelScanner {
    static func scan(processID: pid_t, detectPanel: PanelDetector) -> PanelScanOutcome {
        let application = AXUIElementCreateApplication(processID)
        // パネルの有無は、ウィンドウ一覧を実際に取得できたときだけ判断する。取得エラー（noValue / attributeUnsupported /
        // cannotComplete など）で追跡中のパネルを消えたとみなさないため、すべて unavailable にする。
        // アプリの終了（invalidUIElement）は NSWorkspace の終了通知で扱う
        guard let windowsValue = try? application.copyAttributeValue(kAXWindowsAttribute),
              let windows = AXAttributeCast.cast(windowsValue, to: [AXUIElement].self) else {
            return .unavailable
        }
        return .found(windows.compactMap(detectPanel))
    }
}
