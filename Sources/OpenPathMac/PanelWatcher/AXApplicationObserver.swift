import ApplicationServices

/// 1 つのアプリに対する AXObserver の購読（DSN-001 §2.1）。
///
/// ライフサイクル（呼ぶスレッドが決まっている）:
/// 1. `register(processID:notifications:handler:)`（axQueue）: AXObserver の生成と通知の登録。登録はプロセス間通信のため axQueue で行う
/// 2. `schedule()`（main）: main の RunLoop にソースを追加する。以降、コールバックは main スレッドで届く
/// 3. `unschedule()`（main）: RunLoop からソースを外す。以降コールバックは届かない
/// 4. `unregister()`（axQueue）: 通知の登録を解除し、コールバック用の参照を解放する
///
/// 1. から 4. の間は、`observeDestruction(of:)`（axQueue）でパネルの要素にも破棄の通知を追加できる。
///
/// C のコールバックは Swift のクロージャを捕捉できないため、ハンドラを持つ `CallbackTarget` を
/// `Unmanaged` で retain したまま refcon として渡す。解放は 3. の後の 4. で行うので、
/// 解放済みの refcon でコールバックが呼ばれることはない。
///
/// `@unchecked Sendable` の根拠: 上記のとおり呼ぶスレッドを決めてあり、可変状態（`isUnregistered` と
/// `destructionObservedElements`）は axQueue でのみ触る。
/// それ以外のプロパティは生成後に変わらない。
final class AXApplicationObserver: @unchecked Sendable {
    /// 通知名と、通知の対象の要素を受け取る。main スレッドで呼ばれる。
    typealias Handler = @MainActor (_ notification: String, _ element: AXUIElement) -> Void

    /// `observeDestruction(of:)` で破棄の通知を登録しておく要素の数の上限。1 つのアプリを観測している間に
    /// 開かれたパネルの数だけ増えるため、古いものから登録を外す（破棄済みの要素の登録が残り続けないようにする）。
    private static let maxDestructionObservedElements = 8

    let processID: pid_t
    private let observer: AXObserver
    private let applicationElement: AXUIElement
    private let registeredNotifications: [String]
    private let callbackTarget: Unmanaged<CallbackTarget>
    private var isUnregistered = false
    /// `observeDestruction(of:)` で破棄の通知を登録した要素（古い順）
    private var destructionObservedElements: [AXUIElement] = []

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

    /// パネルの要素（シートなど）にも `kAXUIElementDestroyedNotification` を登録する。axQueue で呼ぶこと。
    ///
    /// アプリ要素への登録でも子要素の破棄は届く想定だが、実機で確かめられていない。PanelShown 中は補助ポーリングを
    /// 止めているため、パネルが閉じたこと（FR-DETECT-05）を確実に知るよう要素にも重ねて登録する。
    /// 登録済みの要素や、登録できない要素（別プロセスで描画された要素など）は無視する。
    func observeDestruction(of element: AXUIElement) {
        guard !isUnregistered, !destructionObservedElements.contains(element) else { return }
        let result = AXObserverAddNotification(
            observer,
            element,
            kAXUIElementDestroyedNotification as CFString,
            callbackTarget.toOpaque()
        )
        guard result == .success else { return }
        destructionObservedElements.append(element)
        if destructionObservedElements.count > Self.maxDestructionObservedElements {
            let oldest = destructionObservedElements.removeFirst()
            AXObserverRemoveNotification(observer, oldest, kAXUIElementDestroyedNotification as CFString)
        }
    }

    /// 通知の登録を解除し、コールバック用の参照を解放する。`unschedule()` の後に axQueue で 1 回だけ呼ぶこと。
    func unregister() {
        guard !isUnregistered else { return }
        isUnregistered = true
        for notification in registeredNotifications {
            AXObserverRemoveNotification(observer, applicationElement, notification as CFString)
        }
        // 破棄済みの要素では失敗するが、登録は要素とともに消えているため問題ない
        for element in destructionObservedElements {
            AXObserverRemoveNotification(observer, element, kAXUIElementDestroyedNotification as CFString)
        }
        destructionObservedElements = []
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
        target.handler(notificationName, element)
    }
}
