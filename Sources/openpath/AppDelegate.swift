import AppKit

import OpenPathCore
import OpenPathMac

/// アプリのライフサイクルを受け持つ。依存の生成と配線は AppComposition に任せ、ここでは開始と終了だけを伝える。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 以降のログ（起動処理を含む）をファイルにも残すため、他の処理より先に設定する
        Log.configure(LogConfiguration())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("\(AppInfo.name) \(AppInfo.version) を起動します")
        let composition = AppComposition()
        self.composition = composition
        composition.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition?.stop()
        Log.info("\(AppInfo.name) を終了します")
        Log.flush()
    }
}
