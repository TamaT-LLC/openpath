import ApplicationServices
import os

import OpenPathCore

/// NSOpenPanel の判定（DSN-001 §2.2、FR-DETECT-01 / 02）。PanelWatcher の既定の `PanelDetecting`。
///
/// 判定条件・キャッシュ・ID の振り方は OpenPathCore の `OpenPanelLocator` が持ち、ここでは AX の読み取りを渡すだけにする。
/// - ID: パネルの要素（ダイアログのウィンドウ、またはシート）の同一性（CFEqual / CFHash）ごとに振る連番。
///   ⌘⇧G で移動先シートを出してフォルダを移動しても、パネルの要素は変わらないため ID も変わらない
/// - キャッシュ: 要素をキーに持ち、`elementDestroyed(_:)`（kAXUIElementDestroyedNotification）で破棄する
/// - AX の一時的な失敗: 直前にそのウィンドウで見つけたパネルを返し、追跡中のパネルを消えたとみなさない
/// - 選択モード: 開くパネルと判定したときに、ファイル一覧の先頭の行から 1 度だけ推定する（DSN-001 §2.3）
/// - 診断: debug ログを出す設定のときだけ、ウィンドウを初めて見たときと候補を判定したときに、どの条件で弾いたかと
///   子孫の要約を `panel check (…)` として 1 行ずつ出す（Issue #83。文言は `OpenPanelDiagnostic.logMessage`）
///
/// `@unchecked Sendable` の根拠: 可変状態（locator）はロックで守る。メソッドはどちらも axQueue で呼ばれるため、
/// ロックを保持したまま AX を呼び出しても待たされるスレッドはない。
public final class OpenPanelDetector: PanelDetecting, @unchecked Sendable {
    private let locator: OSAllocatedUnfairLock<OpenPanelLocator<AXUIElement>>

    public init(configuration: OpenPanelCacheConfiguration = OpenPanelCacheConfiguration()) {
        locator = OSAllocatedUnfairLock(uncheckedState: OpenPanelLocator(configuration: configuration))
    }

    public func detectPanel(in window: AXUIElement) -> DetectedPanel? {
        let reader = AXPanelTreeReader()
        let target = AXPanelTreeReader.limitingMessagingTimeout(window)
        // 診断のための AX の読み取りは、debug ログを出す設定のときだけ行う
        let collectsDiagnostics = Log.isDebugEnabled
        let startedAt = ContinuousClock.now
        let (lookup, report) = locator.withLockUnchecked { locator -> (OpenPanelLookup<AXUIElement>, OpenPanelDiagnosticReport?) in
            guard collectsDiagnostics else {
                return (locator.locate(in: target, reader: reader, now: startedAt), nil)
            }
            var report = OpenPanelDiagnosticReport()
            let lookup = locator.locate(in: target, reader: reader, now: startedAt, diagnostics: &report)
            return (lookup, report)
        }
        let elapsed = ContinuousClock.now - startedAt
        for entry in report?.entries ?? [] {
            Log.debug(entry.logMessage)
        }
        let diagnosticAXCalls = report?.diagnosticReadCount ?? 0
        Self.log(lookup, axCalls: reader.callCount - diagnosticAXCalls, diagnosticAXCalls: diagnosticAXCalls, elapsed: elapsed)
        return lookup.panel.map {
            DetectedPanel(element: $0.element, context: $0.context, selectionEstimate: $0.selectionEstimate)
        }
    }

    public func elementDestroyed(_ element: AXUIElement) {
        locator.withLockUnchecked { locator in
            locator.forget(element)
        }
    }

    /// 判定のコスト（AX 呼び出しの回数と所要時間。選択モードの推定を含む）と推定結果を残す。
    /// パネルの出現そのものは PanelWatcher が `panel detected` で記録する。
    /// - Parameters:
    ///   - axCalls: 判定のための AX 呼び出しの回数。診断のための読み取り（diagnosticAXCalls）は含めない。
    ///   - diagnosticAXCalls: 診断のためだけの読み取りの回数。elapsed にはこの分の時間も含まれる。
    private static func log(_ lookup: OpenPanelLookup<AXUIElement>, axCalls: Int, diagnosticAXCalls: Int, elapsed: Duration) {
        switch lookup {
        case .found(let panel) where panel.isNewlyClassified:
            let diagnostics = diagnosticAXCalls > 0 ? ", diagnosticAXCalls: \(diagnosticAXCalls)" : ""
            Log.debug(
                "open panel classified (id: \(panel.context.id.rawValue), selectionMode: \(panel.selectionMode), "
                    + "axCalls: \(axCalls), elapsedMs: \(elapsed.wholeMilliseconds)\(diagnostics))"
            )
        case .undetermined(let lastKnown):
            Log.debug(
                "panel detection undetermined (keepsLastPanel: \(lastKnown != nil), axCalls: \(axCalls), elapsedMs: \(elapsed.wholeMilliseconds))"
            )
        case .found, .notFound:
            break
        }
    }
}

extension Duration {
    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
    private static let millisecondsPerSecond: Int64 = 1_000

    /// ミリ秒（切り捨て）。ログ用。
    var wholeMilliseconds: Int64 {
        components.seconds * Self.millisecondsPerSecond + components.attoseconds / Self.attosecondsPerMillisecond
    }
}
