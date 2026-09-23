import ApplicationServices

import OpenPathCore

/// 観測中のアプリのウィンドウを列挙してパネルを探す。AX のプロセス間呼び出しを伴うため axQueue で呼ぶこと。
enum PanelScanner {
    struct Scan {
        let outcome: PanelScanOutcome
        /// 見つけたパネルの要素。破棄の通知を登録するために使う
        let panelElements: [AXUIElement]
    }

    static func scan(processID: pid_t, detector: any PanelDetecting) -> Scan {
        let application = AXUIElementCreateApplication(processID)
        // パネルの有無は、ウィンドウ一覧を実際に取得できたときだけ判断する。取得エラー（noValue / attributeUnsupported /
        // cannotComplete など）で追跡中のパネルを消えたとみなさないため、すべて unavailable にする。
        // アプリの終了（invalidUIElement）は NSWorkspace の終了通知で扱う
        guard let windowsValue = try? application.copyAttributeValue(kAXWindowsAttribute),
              let windows = AXAttributeCast.cast(windowsValue, to: [AXUIElement].self) else {
            return Scan(outcome: .unavailable, panelElements: [])
        }
        let panels = windows.compactMap(detector.detectPanel(in:))
        return Scan(outcome: .found(panels.map(\.context)), panelElements: panels.map(\.element))
    }
}
