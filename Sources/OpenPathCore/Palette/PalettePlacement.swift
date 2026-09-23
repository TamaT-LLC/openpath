import CoreGraphics

/// パレットウィンドウの配置計算（UX-001 §3）。
///
/// 入出力の矩形はすべて NSScreen 座標系（左下原点、y は上向き）。
/// AX 座標（左上原点）からの変換は呼び出し側（PanelWatcher）の責務とする。
public enum PalettePlacement {
    /// NSOpenPanel の位置からパレットのフレームを求める。
    ///
    /// 1. パネル右上角から内側へ `panelCornerOffset` ずらした位置にパレットの右上角を合わせる。
    /// 2. それでは可視領域の右端を越える場合は、パネル左上角を基準に同様に置く。
    /// 3. 最後に可視領域内へクランプする。可視領域より大きい場合は検索フィールドのある左上を優先する。
    ///
    /// 上端はパネルの上端から決まり行数に依存しないため、候補数が変わっても検索フィールドは動かない。
    public static func frame(
        panelFrame: CGRect,
        visibleScreenFrame: CGRect,
        rowCount: Int,
        metrics: PaletteMetrics = .standard
    ) -> CGRect {
        let size = metrics.size(rowCount: rowCount)
        let offset = metrics.panelCornerOffset

        let topRightAlignedMinX = panelFrame.maxX - offset - size.width
        let fitsTopRight = topRightAlignedMinX + size.width <= visibleScreenFrame.maxX
        let minX = fitsTopRight ? topRightAlignedMinX : panelFrame.minX + offset
        let maxY = panelFrame.maxY - offset

        let unclamped = CGRect(x: minX, y: maxY - size.height, width: size.width, height: size.height)
        return clamp(unclamped, into: visibleScreenFrame)
    }

    /// パネルの配置先とすべき画面を `screenFrames` の添字で返す。
    ///
    /// パネルと最も広く重なる画面を選び、どの画面とも重ならない場合は中心が最も近い画面を選ぶ。
    /// 画面がない場合は nil。
    public static func screenIndex(for panelFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        let intersectionAreas = screenFrames.map { area(of: $0.intersection(panelFrame)) }
        if let largestIndex = intersectionAreas.indices.max(by: { intersectionAreas[$0] < intersectionAreas[$1] }),
           intersectionAreas[largestIndex] > 0 {
            return largestIndex
        }

        let panelCenter = center(of: panelFrame)
        return screenFrames.indices.min { lhs, rhs in
            squaredDistance(center(of: screenFrames[lhs]), panelCenter)
                < squaredDistance(center(of: screenFrames[rhs]), panelCenter)
        }
    }

    private static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        let x = rect.width > bounds.width
            ? bounds.minX
            : min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        let y = rect.height > bounds.height
            ? bounds.maxY - rect.height
            : min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}
