import AppKit

import OpenPathCore

/// `StatusItemDialog` を NSAlert でモーダル表示する。
@MainActor
enum StatusItemAlert {
    private static let escapeKeyEquivalent = "\u{1b}"

    /// - Returns: 選ばれたボタンの `dialog.buttons` での位置。判別できなければ nil
    @discardableResult
    static func run(_ dialog: StatusItemDialog) -> Int? {
        let alert = NSAlert()
        alert.messageText = dialog.title
        alert.informativeText = dialog.message
        for button in dialog.buttons {
            let alertButton = alert.addButton(withTitle: button.title)
            switch button.role {
            case .default:
                break
            case .destructive:
                alert.alertStyle = .warning
                alertButton.hasDestructiveAction = true
            case .cancel:
                alertButton.keyEquivalent = escapeKeyEquivalent
            }
        }

        // 常駐アプリ（accessory）は前面にいないため、前面に出さないとダイアログが他のウインドウの裏に隠れる
        NSApplication.shared.activate()
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return dialog.buttons.indices.contains(index) ? index : nil
    }
}
