import AppKit

import OpenPathCore

/// `StatusMenuState` の並びを NSMenu の項目に反映する。
///
/// 項目で選ばれた操作は `representedObject` の `StatusMenuCommand` で送り先に伝える。
@MainActor
struct StatusMenuRenderer {
    private enum Constants {
        static let noticeSymbolName = "exclamationmark.triangle"
        /// 通知の説明を折り返す幅（pt）。メニューが横に広がりすぎないようにする
        static let noticeDetailMaxWidth: CGFloat = 320
        /// NSFont.menuFont(ofSize:) に 0 を渡すとメニューの既定の大きさになる
        static let defaultMenuFontSize: CGFloat = 0
        static let newline = "\n"
    }

    /// 選ばれた項目の送り先
    let target: AnyObject
    let action: Selector
    /// 実行先が配線されているか。配線されていない操作は選べないようにする
    let canPerform: (StatusMenuCommand) -> Bool

    func render(_ state: StatusMenuState, into menu: NSMenu) {
        menu.removeAllItems()
        for entry in state.entries {
            menu.addItem(makeItem(for: entry))
        }
    }

    private func makeItem(for entry: StatusMenuEntry) -> NSMenuItem {
        switch entry {
        case .notice(let notice):
            return makeNoticeItem(notice)
        case .command(let item):
            return makeCommandItem(item)
        case .separator:
            return .separator()
        }
    }

    private func makeCommandItem(_ item: StatusMenuItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.title, action: action, keyEquivalent: item.keyEquivalent)
        menuItem.target = target
        menuItem.representedObject = item.command
        menuItem.isEnabled = item.isEnabled && canPerform(item.command)
        menuItem.toolTip = item.toolTip
        if let checkState = item.checkState {
            menuItem.state = Self.controlState(for: checkState)
        }
        return menuItem
    }

    /// 表題と、折り返した説明を 1 項目にまとめる。選ぶと原因の解消へ案内する
    private func makeNoticeItem(_ notice: StatusNotice) -> NSMenuItem {
        let menuItem = NSMenuItem(title: notice.title, action: action, keyEquivalent: "")
        menuItem.attributedTitle = Self.noticeTitle(notice)
        menuItem.image = NSImage(systemSymbolName: Constants.noticeSymbolName, accessibilityDescription: nil)
        menuItem.toolTip = notice.detail
        menuItem.target = target
        menuItem.representedObject = notice.command
        menuItem.isEnabled = canPerform(notice.command)
        return menuItem
    }

    private static func noticeTitle(_ notice: StatusNotice) -> NSAttributedString {
        let titleFont = NSFont.menuFont(ofSize: Constants.defaultMenuFontSize)
        let detailFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: detailFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let detailLines = TextLineWrapper.wrap(notice.detail, maxWidth: Double(Constants.noticeDetailMaxWidth)) { text in
            Double(NSAttributedString(string: text, attributes: detailAttributes).size().width)
        }

        let title = NSMutableAttributedString(string: notice.title, attributes: [.font: titleFont])
        for line in detailLines {
            title.append(NSAttributedString(string: Constants.newline + line, attributes: detailAttributes))
        }
        return title
    }

    private static func controlState(for checkState: StatusMenuCheckState) -> NSControl.StateValue {
        switch checkState {
        case .on: .on
        case .off: .off
        case .mixed: .mixed
        }
    }
}
