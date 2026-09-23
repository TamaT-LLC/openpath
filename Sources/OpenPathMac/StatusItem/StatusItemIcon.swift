import AppKit

import OpenPathCore

/// メニューバーのアイコン画像。
///
/// ライト / ダーク表示と選択中の反転に追従させるため、バッジ付きも含めてテンプレート画像にする。
/// バッジは色を使えないため、右上を丸くくり抜いて点を置き、フォルダの輪郭と見分けられるようにする。
enum StatusItemIcon {
    private static let symbolName = "folder"
    /// 点の直径（アイコンの高さに対する比）
    private static let badgeDiameterRatio: CGFloat = 0.5
    /// 点の周りをくり抜く幅（pt）
    private static let badgeCutoutWidth: CGFloat = 1.5

    /// - Returns: SF Symbols を読み込めなければ nil（呼び出し側で文字の表示に切り替える）
    static func image(for state: StatusIconState) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.accessibilityLabel) else {
            return nil
        }
        let image = state.hasBadge ? badged(symbol) : symbol
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityLabel
        return image
    }

    private static func badged(_ symbol: NSImage) -> NSImage {
        let diameterRatio = badgeDiameterRatio
        let cutoutWidth = badgeCutoutWidth
        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            guard let context = NSGraphicsContext.current else { return true }

            let diameter = rect.height * diameterRatio
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSColor.black.setFill()

            context.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dot.insetBy(dx: -cutoutWidth, dy: -cutoutWidth)).fill()
            context.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }
}
