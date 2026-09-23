import OpenPathCore

/// アプリのコンポジションルート。依存の生成と配線を AppDelegate から切り離す。
///
/// AppDelegate は起動時に生成して `start()`、終了時に `stop()` を呼ぶだけにする。
/// - 各モジュールの生成と配線、段階ごとの開始・停止の実体: `AppServices`
/// - 起動・終了の順番と、アクセシビリティ権限によるパネルの監視の開始・停止: OpenPathCore の `AppLifecycle`
/// - 権限の変化の監視（`AccessibilityPermissionMonitor`）と、メニューバー（`StatusItemController`）はここで持つ。
///   監視の通知先は 1 つしか持てないため、AppLifecycle とメニューバーの両方へここで振り分ける。
@MainActor
public final class AppComposition {
    private let services: AppServices
    private let lifecycle: AppLifecycle
    private let permissionMonitor: AccessibilityPermissionMonitor
    private let statusItemController: StatusItemController
    private var launchTask: Task<Void, Never>?

    public init() {
        let services = AppServices()
        let permissionMonitor = AccessibilityPermissionMonitor()
        self.services = services
        self.permissionMonitor = permissionMonitor
        lifecycle = AppLifecycle(services: services, permission: permissionMonitor.status)
        statusItemController = StatusItemController(
            configFileURL: services.configStore.fileURL,
            accessibilityPermission: permissionMonitor.status
        )
        permissionMonitor.onChange = { [weak self] status in
            self?.permissionDidChange(status)
        }
    }

    /// 起動する。設定を読み込んでから候補の構築・パネルの監視・ホットキーを始める。2 回目以降は何もしない。
    public func start() {
        guard launchTask == nil else { return }
        permissionMonitor.start()
        let lifecycle = lifecycle
        launchTask = Task {
            await lifecycle.launch()
        }
    }

    /// 終了する。パネルの監視とホットキーを止め、履歴を保存し、候補の構築と設定の監視を止める。
    /// ログの書き出し（`Log.flush()`）は呼び出し側で最後に行う。
    public func stop() {
        permissionMonitor.stop()
        lifecycle.terminate()
    }

    private func permissionDidChange(_ status: AccessibilityPermissionStatus) {
        statusItemController.setAccessibilityPermission(status)
        lifecycle.permissionDidChange(status)
    }
}
