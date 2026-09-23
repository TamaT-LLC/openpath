import ApplicationServices

/// 1 つのアプリに対する AXObserver の購読（DSN-001 §2.1）。
///
/// ライフサイクル（呼ぶスレッドが決まっている）:
/// 1. `register(processID:notifications:handler:)`（axQueue）: AXObserver の生成と通知の登録。登録はプロセス間通信のため axQueue で行う
/// 2. `schedule()`（main）: main の RunLoop にソースを追加する。以降、コールバックは main スレッドで届く
/// 3. `unschedule()`（main）: RunLoop からソースを外す。以降コールバックは届かない
/// 4. `unregister()`（axQueue）: 通知の登録を解除し、コールバック用の参照を解放する
///
/// C のコールバックは Swift のクロージャを捕捉できないため、ハンドラを持つ `CallbackTarget` を
/// `Unmanaged` で retain したまま refcon として渡す。解放は 3. の後の 4. で行うので、
/// 解放済みの refcon でコールバックが呼ばれることはない。
///
/// `@unchecked Sendable` の根拠: 上記のとおり呼ぶスレッドを決めてあり、可変状態（`isUnregistered`）は axQueue でのみ触る。
/// それ以外のプロパティは生成後に変わらない。
final class AXApplicationObserver: @unchecked Sendable {
    /// 通知名を受け取る。main スレッドで呼ばれる。
    typealias Handler = @MainActor (_ notification: String) -> Void

    let processID: pid_t
    private let observer: AXObserver
    private let applicationElement: AXUIElement
    private let registeredNotifications: [String]
    private let callbackTarget: Unmanaged<CallbackTarget>
    private var isUnregistered = false

    private init(
        processID: pid_t,
        observer: AXObserver,
        applicationElement: AXUIElement,
        registeredNotifications: [String],
        callbackTarget: Unmanaged<CallbackTarget>
    ) {
        self.processID = processID
        self.observer = observer
        self.applicationElement = applicationElement
        self.registeredNotifications = registeredNotifications
        self.callbackTarget = callbackTarget
    }

    /// AXObserver を生成し、アプリ要素に通知を登録する。axQueue で呼ぶこと。
    /// 1 つでも登録できなければ失敗とする。一部の通知（要素破棄など）が欠けるとパネルの消滅を取りこぼすため、
    /// 呼び出し側はポーリングで補う。
    static func register(
        processID: pid_t,
        notifications: [String],
        handler: @escaping Handler
    ) -> Result<AXApplicationObserver, AXElementError> {
        var createdObserver: AXObserver?
        let createResult = AXObserverCreate(processID, axObserverCallback, &createdObserver)
        guard createResult == .success, let observer = createdObserver else {
            return .failure(AXElementError(code: createResult, target: "AXObserverCreate"))
        }

        let applicationElement = AXUIElementCreateApplication(processID)
        let callbackTarget = Unmanaged.passRetained(CallbackTarget(handler: handler))
        var registered: [String] = []
        for notification in notifications {
            let result = AXObserverAddNotification(
                observer,
                applicationElement,
                notification as CFString,
                callbackTarget.toOpaque()
            )
            guard result == .success else {
                // ソースを RunLoop に追加する前なので、登録済みの通知を外せばコールバックは届かない
                for registeredNotification in registered {
                    AXObserverRemoveNotification(observer, applicationElement, registeredNotification as CFString)
                }
                callbackTarget.release()
                return .failure(AXElementError(code: result, target: notification))
            }
            registered.append(notification)
        }
        return .success(AXApplicationObserver(
            processID: processID,
            observer: observer,
            applicationElement: applicationElement,
            registeredNotifications: registered,
            callbackTarget: callbackTarget
        ))
    }

    /// main の RunLoop にソースを追加し、通知を受け取り始める。main で呼ぶこと。
    /// メニュー操作中など RunLoop が既定以外のモードで回っていても通知を落とさないよう、common モードに追加する。
    func schedule() {
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// main の RunLoop からソースを外す。main で呼ぶこと。
    func unschedule() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// 通知の登録を解除し、コールバック用の参照を解放する。`unschedule()` の後に axQueue で 1 回だけ呼ぶこと。
    func unregister() {
        guard !isUnregistered else { return }
        isUnregistered = true
        for notification in registeredNotifications {
            AXObserverRemoveNotification(observer, applicationElement, notification as CFString)
        }
        callbackTarget.release()
    }
}

/// C コールバックから Swift のハンドラへ戻るための入れ物。
private final class CallbackTarget {
    let handler: AXApplicationObserver.Handler

    init(handler: @escaping AXApplicationObserver.Handler) {
        self.handler = handler
    }
}

/// AXObserver の C コールバック。ソースを main の RunLoop にだけ追加しているため main スレッドで呼ばれる。
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let target = Unmanaged<CallbackTarget>.fromOpaque(refcon).takeUnretainedValue()
    let notificationName = notification as String
    MainActor.assumeIsolated {
        target.handler(notificationName)
    }
}
