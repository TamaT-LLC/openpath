import ApplicationServices
import Dispatch

import OpenPathCore

/// PanelWatchEngine の AX 側の実体。AXObserver の張り替えとパネルの走査を行う。
@MainActor
final class AXPanelWatchEnvironment: PanelWatchEnvironment {
    /// 購読する通知（DSN-001 §2.1）。
    private static let observedNotifications = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    /// 観測中のアプリから AX 通知が届いたときに、そのプロセス ID を渡して呼ぶ。
    var onNotification: ((pid_t) -> Void)?
    /// AXObserver を張れなかったときに、そのプロセス ID を渡して呼ぶ。
    var onObservationFailure: ((pid_t) -> Void)?

    private let detector: any PanelDetecting
    private var observer: AXApplicationObserver?
    /// attach / detach のたびに増やす。axQueue での登録中に張り替えが起きた場合、古い登録を捨てるために使う
    private var attachGeneration = 0
    /// 直前の走査で見つけたパネルの選択モードの推定結果（パネルの ID ごと）
    private var selectionEstimates: [PanelContext.ID: PanelSelectionEstimate] = [:]

    init(detector: any PanelDetecting) {
        self.detector = detector
    }

    deinit {
        // 通常は PanelWatcher.stop() で外れている。外し忘れても解放済みの参照でコールバックされないよう、同じ手順で外す
        guard let observer else { return }
        observer.unschedule()
        axQueue.async {
            observer.unregister()
        }
    }

    func attach(processID: Int32) {
        detach()
        let generation = attachGeneration
        let notifications = Self.observedNotifications
        let detector = detector
        let handler: AXApplicationObserver.Handler = { [weak self] notification, element in
            if notification == kAXUIElementDestroyedNotification {
                // 判定のキャッシュを捨てる。この後の走査より先に axQueue で処理されるよう、走査の依頼より前に積む
                let destroyed = DestroyedElement(element: element)
                axQueue.async {
                    detector.elementDestroyed(destroyed.element)
                }
            }
            self?.onNotification?(processID)
        }
        Task { [weak self] in
            let result = await onAXQueue {
                AXApplicationObserver.register(
                    processID: processID,
                    notifications: notifications,
                    handler: handler
                )
            }
            guard let self, self.attachGeneration == generation else {
                if case .success(let staleObserver) = result {
                    axQueue.async {
                        staleObserver.unregister()
                    }
                }
                return
            }
            switch result {
            case .success(let observer):
                observer.schedule()
                self.observer = observer
            case .failure:
                // 観測は外さず、PanelShown 中もポーリングを続けてもらう（通知の代わりにパネルの消滅を検知する）
                self.onObservationFailure?(processID)
            }
        }
    }

    func detach() {
        attachGeneration += 1
        guard let observer else { return }
        self.observer = nil
        // 先に main でソースを外し、コールバックが届かなくなってから axQueue で登録解除と参照の解放を行う
        observer.unschedule()
        axQueue.async {
            observer.unregister()
        }
    }

    func scanPanels(processID: Int32) async -> PanelScanOutcome {
        let detector = detector
        // 張り替え中なら、別のアプリの observer にパネルの要素を登録しない
        let observer = observer.flatMap { $0.processID == processID ? $0 : nil }
        let (outcome, estimates) = await onAXQueue {
            let scan = PanelScanner.scan(processID: processID, detector: detector)
            for element in scan.panelElements {
                observer?.observeDestruction(of: element)
            }
            return (scan.outcome, scan.selectionEstimates)
        }
        // ウィンドウ一覧を読めなかった走査では、追跡中のパネルを消えたとみなさないため、直前の推定結果も残す
        if case .found = outcome {
            selectionEstimates = estimates
        }
        return outcome
    }

    /// 直前の走査で見つけたパネルの選択モードの推定結果。PanelWatcher がログ（`panel detected` 等）に出すために使う。
    /// 走査の結果を返す前に更新するため、その走査で送られるイベントのログには、同じ走査の推定結果が出る。
    func selectionEstimate(for panelID: PanelContext.ID) -> PanelSelectionEstimate? {
        selectionEstimates[panelID]
    }
}

/// 破棄された要素を axQueue へ渡すための入れ物。
/// `@unchecked Sendable` の根拠: AXUIElement は生成後に変わらない参照で、参照カウントの操作はスレッドセーフ。
/// 受け取った側（判定のキャッシュ）は要素を比較に使うだけで、AX の呼び出しはしない。
private struct DestroyedElement: @unchecked Sendable {
    let element: AXUIElement
}
