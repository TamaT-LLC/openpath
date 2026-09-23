import AppKit

import OpenPathCore

/// 初回起動の案内（UX-001 §7）を構成する部品（ウインドウ・「試してみる」・案内を終えたかの記録）を生成して保持し、
/// OnboardingController の副作用の実行先になる。
///
/// 案内を終えたか（完了・スキップ）は UserDefaults（`jp.tamat.openpath`）に記録する。判定の方針は `UserDefaultsOnboardingRecord` を参照。
@MainActor
final class OnboardingAssembly {
    private let window = OnboardingWindow()
    private let trialLauncher = TrialOpenPanelLauncher()
    private let configStore: ConfigStore
    /// 自身を services として渡すため、他のプロパティを初期化した後で作る
    private var controller: OnboardingController?
    private var configPreparationTask: Task<Void, Never>?

    /// - Parameters:
    ///   - configStore: 権限を付与した後に、設定ファイルが無ければ既定値で生成する（`createFileIfMissing()`）
    ///   - permission: 生成時のアクセシビリティ権限の状態
    init(configStore: ConfigStore, permission: AccessibilityPermissionStatus) {
        self.configStore = configStore
        let controller = OnboardingController(
            services: self,
            record: UserDefaultsOnboardingRecord(storage: UserDefaults.standard),
            permission: permission
        )
        self.controller = controller
        window.onCommand = { [weak controller] command in
            controller?.perform(command)
        }
    }

    /// 起動処理（設定の読み込み・パネルの監視の開始）を終えたときに 1 度呼ぶ。初回なら案内を出す。
    func launched() {
        controller?.launched()
    }

    /// メニューの「はじめに…」
    func reopen() {
        controller?.reopen()
    }

    func permissionDidChange(_ permission: AccessibilityPermissionStatus) {
        controller?.permissionDidChange(permission)
    }

    /// アプリの終了時に呼ぶ。「試してみる」のダイアログ（osascript）を残さない。
    /// 終了の途中で閉じられた案内を「スキップ」と記録しないよう、以降のウインドウからの知らせは受け取らない。
    func stop() {
        window.onCommand = nil
        configPreparationTask?.cancel()
        configPreparationTask = nil
        trialLauncher.terminate()
        window.dismiss()
    }
}

extension OnboardingAssembly: OnboardingServices {
    func presentOnboarding(_ page: OnboardingPage) {
        window.present(page)
    }

    func dismissOnboarding() {
        window.dismiss()
    }

    func openAccessibilitySettings() {
        if !AccessibilityPermission.openSystemSettings() {
            Log.warning("システム設定のアクセシビリティを開けませんでした")
        }
    }

    func prepareConfigFile() {
        guard configPreparationTask == nil else { return }
        let configStore = configStore
        configPreparationTask = Task { [weak self] in
            await configStore.createFileIfMissing()
            self?.configPreparationTask = nil
        }
    }

    func launchTrialPanel() {
        trialLauncher.launch()
    }
}
