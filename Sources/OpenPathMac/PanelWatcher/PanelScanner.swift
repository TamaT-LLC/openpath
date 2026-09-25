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

    /// - Parameters:
    ///   - bundleIdentifier: 観測中のアプリの bundle id。debug ログ（走査の要約）に出すだけに使う。
    ///   - diagnostics: 走査の要約の debug ログ。ウィンドウの判定より先に出す。
    static func scan(
        processID: pid_t,
        bundleIdentifier: String?,
        detector: any PanelDetecting,
        diagnostics: PanelScanDiagnostics
    ) -> Scan {
        let application = AXUIElementCreateApplication(processID)
        // パネルの有無は、ウィンドウ一覧を実際に取得できたときだけ判断する。取得エラー（noValue / attributeUnsupported /
        // cannotComplete など）で追跡中のパネルを消えたとみなさないため、すべて unavailable にする。
        // アプリの終了（invalidUIElement）は NSWorkspace の終了通知で扱う
        let windowsValue: CFTypeRef
        do {
            windowsValue = try application.copyAttributeValue(kAXWindowsAttribute)
        } catch {
            let code = (error as? AXElementError)?.code.rawValue
            diagnostics.record(processID: processID, bundleIdentifier: bundleIdentifier, windowCount: nil, axErrorCode: code)
            return Scan(outcome: .unavailable, panelElements: [], selectionEstimates: [:])
        }
        guard let windows = AXAttributeCast.cast(windowsValue, to: [AXUIElement].self) else {
            diagnostics.record(processID: processID, bundleIdentifier: bundleIdentifier, windowCount: nil, axErrorCode: nil)
            return Scan(outcome: .unavailable, panelElements: [], selectionEstimates: [:])
        }
        diagnostics.record(processID: processID, bundleIdentifier: bundleIdentifier, windowCount: windows.count, axErrorCode: nil)
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

/// 走査の要約（どのアプリのウィンドウを何枚見たか）の debug ログ（Issue #83）。
/// 200ms ごとのポーリングで同じ行が並ばないよう、直前に出したものと変わったときだけ出す。
///
/// `@unchecked Sendable` の根拠: 可変状態（`log`）は、走査と同じく axQueue でだけ触る。
final class PanelScanDiagnostics: @unchecked Sendable {
    private var log = PanelScanSummaryLog()

    func record(processID: pid_t, bundleIdentifier: String?, windowCount: Int?, axErrorCode: Int32?) {
        guard Log.isDebugEnabled else { return }
        let summary = PanelScanSummary(
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            windowCount: windowCount,
            axErrorCode: axErrorCode
        )
        guard let message = log.messageIfChanged(summary) else { return }
        Log.debug(message)
    }
}
