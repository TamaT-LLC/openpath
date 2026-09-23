import CoreGraphics

/// AX の座標系の矩形を、NSScreen の座標系の矩形へ変換する（DSN-001 §2.4）。
///
/// どちらも、プライマリディスプレイ（メニューバーのある画面。`NSScreen.screens[0]`、`CGMainDisplayID()`）を基準にした
/// ポイント単位のグローバル座標で、違うのは原点と y 軸の向きだけ:
/// - AX（Quartz のグローバル座標）: プライマリの左上が原点、y は下向き
/// - NSScreen（Cocoa のグローバル座標）: プライマリの左下が原点、y は上向き
///
/// そのため、プライマリの高さで y を反転するだけで、どのディスプレイ上の矩形も変換できる。
/// メイン以外のディスプレイ（上下左右のどこに置いても、負の座標でも）に特別な扱いは要らない。
/// 単位はピクセルではなくポイントなので、Retina と非 Retina が混在していても倍率は関係しない。
public struct ScreenCoordinateConverter: Equatable, Sendable {
    /// プライマリディスプレイの高さ（ポイント）。
    public let primaryScreenHeight: CGFloat

    public init(primaryScreenHeight: CGFloat) {
        self.primaryScreenHeight = primaryScreenHeight
    }

    /// AX の矩形（`kAXPosition` / `kAXSize`）を NSScreen の座標系へ変換する。x と大きさは変わらない。
    public func screenRect(fromAXRect axRect: CGRect) -> CGRect {
        // AX の下端（maxY）が NSScreen の下端（minY）になる
        CGRect(
            x: axRect.minX,
            y: primaryScreenHeight - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }
}
