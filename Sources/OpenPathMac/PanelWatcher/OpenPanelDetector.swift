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
        let startedAt = ContinuousClock.now
        let lookup = locator.withLockUnchecked { locator in
            locator.locate(in: target, reader: reader, now: startedAt)
        }
        Self.log(lookup, axCalls: reader.callCount, elapsed: ContinuousClock.now - startedAt)
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
    private static func log(_ lookup: OpenPanelLookup<AXUIElement>, axCalls: Int, elapsed: Duration) {
        switch lookup {
        case .found(let panel) where panel.isNewlyClassified:
            Log.debug(
                "open panel classified (id: \(panel.context.id.rawValue), selectionMode: \(panel.selectionMode), "
                    + "axCalls: \(axCalls), elapsedMs: \(elapsed.wholeMilliseconds))"
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
