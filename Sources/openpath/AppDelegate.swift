import AppKit

import OpenPathMac

/// アプリのライフサイクルを受け持つ。
/// 現時点では常駐アイコンの生成のみ。各モジュールの配線は後続タスクで AppCoordinator に集約する。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}
