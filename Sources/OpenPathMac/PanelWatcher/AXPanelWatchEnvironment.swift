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

    private let detectPanel: PanelDetector
    private var observer: AXApplicationObserver?
    /// attach / detach のたびに増やす。axQueue での登録中に張り替えが起きた場合、古い登録を捨てるために使う
    private var attachGeneration = 0

    init(detectPanel: @escaping PanelDetector) {
        self.detectPanel = detectPanel
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
        let handler: AXApplicationObserver.Handler = { [weak self] _ in
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
        let detectPanel = detectPanel
        return await onAXQueue {
            PanelScanner.scan(processID: processID, detectPanel: detectPanel)
        }
    }
}
