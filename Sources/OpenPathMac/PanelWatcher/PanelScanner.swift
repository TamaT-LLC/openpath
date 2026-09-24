import ApplicationServices

import OpenPathCore

/// 観測中のアプリのウィンドウを列挙してパネルを探す。AX のプロセス間呼び出しを伴うため axQueue で呼ぶこと。
///
/// 見つけたパネルの矩形は、AX の座標系（左上原点）から NSScreen の座標系（左下原点）へ変換して返す（DSN-001 §2.4）。
/// PanelWatcher が送る `PanelContext.frame` を、そのまま `PaletteWindow.show(near:)` に渡せるようにするため。
enum PanelScanner {
    struct Scan {
        let outcome: PanelScanOutcome
        /// 見つけたパネルの要素。破棄の通知を登録するために使う
        let panelElements: [AXUIElement]
        /// 見つけたパネルの選択モードの推定結果。ログ（`panel detected` 等）に出すために使う
        let selectionEstimates: [PanelContext.ID: PanelSelectionEstimate]
    }

    static func scan(processID: pid_t, detector: any PanelDetecting) -> Scan {
        let application = AXUIElementCreateApplication(processID)
        // パネルの有無は、ウィンドウ一覧を実際に取得できたときだけ判断する。取得エラー（noValue / attributeUnsupported /
        // cannotComplete など）で追跡中のパネルを消えたとみなさないため、すべて unavailable にする。
        // アプリの終了（invalidUIElement）は NSWorkspace の終了通知で扱う
        guard let windowsValue = try? application.copyAttributeValue(kAXWindowsAttribute),
              let windows = AXAttributeCast.cast(windowsValue, to: [AXUIElement].self) else {
            return Scan(outcome: .unavailable, panelElements: [], selectionEstimates: [:])
        }
        let panels = windows.compactMap(detector.detectPanel(in:))
        let converter = ScreenCoordinateConverter.forCurrentDisplays()
        let contexts = panels.map { panel in
            panel.context.withFrame(converter.screenRect(fromAXRect: panel.context.frame))
        }
        let estimates = panels.reduce(into: [PanelContext.ID: PanelSelectionEstimate]()) { estimates, panel in
            estimates[panel.context.id] = panel.selectionEstimate
        }
        return Scan(outcome: .found(contexts), panelElements: panels.map(\.element), selectionEstimates: estimates)
    }
}
