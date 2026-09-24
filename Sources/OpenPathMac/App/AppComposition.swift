import Foundation

import OpenPathCore

/// アプリのコンポジションルート。依存の生成と配線を AppDelegate から切り離す。
///
/// AppDelegate は起動時に生成して `start()`、終了時に `stop()` を呼ぶだけにする。
/// - 各モジュールの生成と配線、段階ごとの開始・停止の実体: `AppServices`
/// - 起動・終了の順番と、アクセシビリティ権限によるパネルの監視の開始・停止: OpenPathCore の `AppLifecycle`
/// - 権限の変化の監視（`AccessibilityPermissionMonitor`）と、メニューバー（`StatusItemController`）はここで持つ。
///   監視の通知先は 1 つしか持てないため、AppLifecycle とメニューバーの両方へここで振り分ける。
/// - メニューの操作（有効・候補を再構築・履歴をクリア・はじめに…）、設定エラーのバッジ（`ConfigStore.lastError`）、
///   自動確定の後のクリップボードの復元失敗のバッジをメニューバーへつなぐ。
/// - 初回起動の案内（`OnboardingAssembly`、UX-001 §7）は起動処理を終えてから出す。
///   設定ファイルの生成とパネルの監視の開始を済ませ、「試してみる」ですぐにパレットが出るようにするため。
/// - メニューの「有効」は UserDefaults（`jp.tamat.openpath`）に記録し、次の起動は前回の値で始める。
///   メニューのチェックとアイコンの薄い表示も、起動時から記録の値に合わせる。
@MainActor
public final class AppComposition {
    private let services: AppServices
    private let lifecycle: AppLifecycle
    private let permissionMonitor: AccessibilityPermissionMonitor
    private let statusItemController: StatusItemController
    private let onboarding: OnboardingAssembly
    private let configErrorObservation: ObservationRelay<ConfigStoreError?>
    private var launchTask: Task<Void, Never>?

    public init() {
        let services = AppServices()
        let permissionMonitor = AccessibilityPermissionMonitor()
        let lifecycle = AppLifecycle(
            services: services,
            permission: permissionMonitor.status,
            enabledState: UserDefaultsEnabledState(storage: UserDefaults.standard)
        )
        let onboarding = OnboardingAssembly(configStore: services.configStore, permission: permissionMonitor.status)
        let statusItemController = StatusItemController(
            configFileURL: services.configStore.fileURL,
            actions: StatusMenuActions(
                // 「有効」は AppLifecycle が UserDefaults に記録する（設定ファイルには書き戻さない）
                setEnabled: { isEnabled in lifecycle.setEnabled(isEnabled) },
                rebuildCandidates: { services.rebuildCandidates() },
                clearHistory: {
                    // 保存できないまま終了すると次の起動で元の履歴に戻るため、ログだけでなく利用者に知らせる
                    guard !services.clearHistory() else { return }
                    StatusItemAlert.run(.clearHistoryFailure)
                },
                showOnboarding: { onboarding.reopen() }
            ),
            isEnabled: lifecycle.isEnabled,
            accessibilityPermission: permissionMonitor.status
        )
        let configStore = services.configStore
        self.services = services
        self.permissionMonitor = permissionMonitor
        self.lifecycle = lifecycle
        self.statusItemController = statusItemController
        self.onboarding = onboarding
        configErrorObservation = ObservationRelay(read: { configStore.lastError }) { [weak statusItemController] error in
            statusItemController?.setConfigError(error)
        }
        permissionMonitor.onChange = { [weak self] status in
            self?.permissionDidChange(status)
        }
        services.onErrorOutsidePalette = { [weak statusItemController] error in
            guard error == .pasteboardRestoreFailed else { return }
            Log.warning("自動確定の後にクリップボードを元に戻せませんでした")
            statusItemController?.showClipboardRestoreFailure()
        }
    }

    /// 起動する。設定を読み込んでから候補の構築・パネルの監視・ホットキーを始める。2 回目以降は何もしない。
    public func start() {
        guard launchTask == nil else { return }
        permissionMonitor.start()
        let lifecycle = lifecycle
        let onboarding = onboarding
        launchTask = Task {
            await lifecycle.launch()
            // 起動処理の途中で終了した場合は案内を出さない
            guard lifecycle.phase == .running else { return }
            onboarding.launched()
        }
    }

    /// 終了する。パネルの監視とホットキーを止め、履歴を保存し、候補の構築と設定の監視を止める。
    /// ログの書き出し（`Log.flush()`）は呼び出し側で最後に行う。
    public func stop() {
        permissionMonitor.stop()
        configErrorObservation.cancel()
        onboarding.stop()
        lifecycle.terminate()
    }

    private func permissionDidChange(_ status: AccessibilityPermissionStatus) {
        statusItemController.setAccessibilityPermission(status)
        // パネルの監視を先に始め、案内の「試してみる」を出す時点で検知できるようにする
        lifecycle.permissionDidChange(status)
        onboarding.permissionDidChange(status)
    }
}
