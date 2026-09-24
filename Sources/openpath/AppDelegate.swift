import AppKit

import OpenPathCore
import OpenPathMac

/// アプリのライフサイクルを受け持つ。依存の生成と配線は AppComposition に任せ、ここでは開始と終了だけを伝える。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 以降のログ（起動処理を含む）をファイルにも残すため、他の処理より先に設定する。
        // 最小レベルは UserDefaults の logLevel で変えられる（QA でリリースビルドの debug ログを出すため、Issue #74）
        let preferredLevel = UserDefaults.standard.string(forKey: LogConfiguration.minimumLevelPreferenceKey)
        Log.configure(LogConfiguration(minimumLevel: LogConfiguration.minimumLevel(preferenceValue: preferredLevel)))
        Self.logPreferredLevel(preferredLevel)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("\(AppInfo.name) \(AppInfo.version) を起動します")
        let composition = AppComposition()
        self.composition = composition
        composition.start()
    }

    /// 設定で最小レベルを変えたことをログに残す。debug ログはパスを含むため、戻し方も併せて残す。
    private static func logPreferredLevel(_ preferredLevel: String?) {
        guard let preferredLevel else { return }
        let key = LogConfiguration.minimumLevelPreferenceKey
        guard let level = LogLevel(preferenceValue: preferredLevel) else {
            Log.warning("設定 \(key) の値が不正なため、既定のログレベルを使います")
            return
        }
        Log.info("設定 \(key) により、ログの最小レベルを \(level.preferenceValue) にしました（既定に戻す: defaults delete \(AppInfo.bundleIdentifier) \(key)）")
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition?.stop()
        Log.info("\(AppInfo.name) を終了します")
        Log.flush()
    }
}
