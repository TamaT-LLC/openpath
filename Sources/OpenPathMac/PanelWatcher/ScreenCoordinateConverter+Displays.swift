import CoreGraphics

import OpenPathCore

extension ScreenCoordinateConverter {
    /// 現在のディスプレイ構成での変換。ディスプレイの接続や配置は変わり得るため、走査のたびに作る。
    ///
    /// `CGMainDisplayID()` はグローバル座標の原点を持つディスプレイ（メニューバーのある画面。`NSScreen.screens[0]` と同じ）。
    /// NSScreen は main スレッドで使う前提のため、axQueue からも呼べる CoreGraphics の関数で高さを取る。
    static func forCurrentDisplays() -> ScreenCoordinateConverter {
        ScreenCoordinateConverter(primaryScreenHeight: CGDisplayBounds(CGMainDisplayID()).height)
    }
}
