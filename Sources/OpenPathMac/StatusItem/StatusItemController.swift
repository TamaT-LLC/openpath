import AppKit

import OpenPathCore

/// メニューバーの常駐アイコンとメニューを管理する。
/// 現時点では「終了」のみ。有効切替や設定ファイルを開く等のメニューは Issue #26 で追加する。
@MainActor
public final class StatusItemController {
    private enum Constants {
        static let iconSymbolName = "folder"
        static let quitMenuTitle = "終了"
        static let quitKeyEquivalent = "q"
    }

    private let statusItem: NSStatusItem

    public init(statusBar: NSStatusBar = .system) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        statusItem.menu = makeMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let icon = NSImage(systemSymbolName: Constants.iconSymbolName, accessibilityDescription: AppInfo.name) {
            // テンプレート画像にしてメニューバーのライト / ダーク表示に追従させる
            icon.isTemplate = true
            button.image = icon
        } else {
            button.title = AppInfo.name
        }
        button.toolTip = AppInfo.name
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: Constants.quitMenuTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: Constants.quitKeyEquivalent
        )
        // ウィンドウを持たない常駐アプリなので、レスポンダチェーンに頼らず送り先を明示する
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)
        return menu
    }
}
