import AppKit
import ApplicationServices

import OpenPathCore

/// 最前面アプリの NSOpenPanel の出現・消滅を検知する（DSN-001 §2.1、ARCH-001 §6）。
///
/// - `NSWorkspace.didActivateApplicationNotification` で最前面アプリの切り替えを追い、AXObserver を張り替える
/// - AXObserver の通知（ウィンドウ生成・要素破棄・フォーカスウィンドウ変更）と、AppCoordinator が Idle の間の
///   200ms 間隔の補助ポーリングでウィンドウを走査し、`detector` でパネルかどうかを判定する
/// - パネルの出現・消滅は `onEvent` に `CoordinatorEvent.panelAppeared` / `.panelGone` として渡し、ログにも残す
///   （`panel detected` はスモークテストとレイテンシ計測に使う。TST-001 §4）
///
/// どのアプリに張り付くか、ポーリングの開始・停止、重複通知の抑止は OpenPathCore の `PanelWatchPolicy` で決める。
/// このクラスはそれを NSWorkspace と AX に接続するだけにしている。
///
/// 配線の例（#27）:
/// ```swift
/// watcher.onEvent = { [weak coordinator] event in coordinator?.handle(event) }
/// coordinator.onStateChange = { [weak watcher] state in watcher?.coordinatorStateDidChange(state) }
/// ```
@MainActor
public final class PanelWatcher {
    /// パネルの出現・消滅。MainActor で呼ばれる。
    /// この中から同期的に `coordinatorStateDidChange(_:)` が呼ばれても、現在の処理を終えてから順に反映する。
    public var onEvent: ((CoordinatorEvent) -> Void)?

    /// 監視中か。
    public var isRunning: Bool {
        engine.isRunning
    }

    private let workspace: NSWorkspace
    private let environment: AXPanelWatchEnvironment
    private let engine: PanelWatchEngine
    private var workspaceObservers: [NSObjectProtocol] = []

    /// 生成しただけでは監視しない。アクセシビリティ権限を確認してから `start()` を呼ぶこと（DSN-001 §6）。
    /// - Parameters:
    ///   - detector: パネル判定。axQueue で呼ばれる。既定は NSOpenPanel の判定（DSN-001 §2.2）。
    ///   - isAppDisabled: bundle id が設定 `disabled_apps` に含まれるか。MainActor で、アプリの切り替えのたびに呼ぶ。
    ///   - workspace: 最前面アプリの取得と通知の購読に使う。
    public init(
        detector: any PanelDetecting = OpenPanelDetector(),
        isAppDisabled: @escaping (String) -> Bool = { _ in false },
        workspace: NSWorkspace = .shared
    ) {
        self.workspace = workspace
        let environment = AXPanelWatchEnvironment(detector: detector)
        let engine = PanelWatchEngine(
            ownProcessID: ProcessInfo.processInfo.processIdentifier,
            environment: environment,
            isAppDisabled: isAppDisabled
        )
        environment.onNotification = { [weak engine] processID in
            engine?.axNotificationDidArrive(processID: processID)
        }
        environment.onObservationFailure = { [weak engine] processID in
            engine?.axObservationDidFail(processID: processID)
        }
        self.environment = environment
        self.engine = engine
        engine.onEvent = { [weak self] event in
            Self.log(event)
            self?.onEvent?(event)
        }
    }

    deinit {
        let notificationCenter = workspace.notificationCenter
        for observer in workspaceObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    /// 監視を始める。監視中なら何もしない。
    public func start() {
        guard !engine.isRunning else { return }
        observeWorkspace()
        engine.start(frontmost: workspace.frontmostApplication.map(ActiveApplication.init(_:)))
    }

    /// 監視をやめる（権限の取り消し、メニューバーでの無効化など）。パネルを追跡中なら `panelGone` を送る。
    public func stop() {
        removeWorkspaceObservers()
        engine.stop()
    }

    /// AppCoordinator の状態が変わったときに呼ぶ。PanelShown / Injecting の間は補助ポーリングを止め、Idle に戻ると再開する。
    /// Idle に戻った時点でパネルが開いたままなら、`panelAppeared` をもう一度送る。
    public func coordinatorStateDidChange(_ state: CoordinatorState) {
        engine.coordinatorStateDidChange(state)
    }

    /// 設定 `disabled_apps` が変わったときに呼ぶ。最前面のアプリを判定し直す。
    public func disabledAppsDidChange() {
        engine.disabledAppsDidChange()
    }

    // MARK: - NSWorkspace

    private func observeWorkspace() {
        let notificationCenter = workspace.notificationCenter
        // queue に main を指定しているため、ブロックは main スレッドで呼ばれる
        workspaceObservers = [
            notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = Self.runningApplication(in: notification) else { return }
                let activeApplication = ActiveApplication(application)
                MainActor.assumeIsolated {
                    self?.engine.applicationDidActivate(activeApplication)
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = Self.runningApplication(in: notification) else { return }
                let processID = application.processIdentifier
                MainActor.assumeIsolated {
                    self?.engine.applicationDidTerminate(processID: processID)
                }
            },
        ]
    }

    private func removeWorkspaceObservers() {
        let notificationCenter = workspace.notificationCenter
        for observer in workspaceObservers {
            notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
    }

    private nonisolated static func runningApplication(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    // MARK: - ログ

    /// 検知の時刻はログのタイムスタンプ（ミリ秒）で分かる。パスは含まない。
    private static func log(_ event: CoordinatorEvent) {
        switch event {
        case .panelAppeared(let panel):
            Log.info("panel detected (id: \(panel.id.rawValue), directoriesOnly: \(panel.isDirectoriesOnly))")
        case .panelGone:
            Log.info("panel gone")
        case .panelContextChanged(let panel):
            Log.info("panel updated (id: \(panel.id.rawValue), directoriesOnly: \(panel.isDirectoriesOnly))")
        case .confirm, .escape, .hotkey:
            break
        }
    }
}

extension ActiveApplication {
    init(_ application: NSRunningApplication) {
        self.init(processID: application.processIdentifier, bundleIdentifier: application.bundleIdentifier)
    }
}
