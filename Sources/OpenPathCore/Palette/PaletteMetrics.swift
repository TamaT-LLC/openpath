import CoreGraphics

/// パレットの寸法（UX-001 §3）。
/// ウィンドウの配置計算と SwiftUI ビューのレイアウトが同じ値を参照し、両者がずれないようにする。
public struct PaletteMetrics: Sendable, Equatable {
    /// パレットの幅
    public let width: CGFloat
    /// 候補 1 行の高さ
    public let rowHeight: CGFloat
    /// 一度に表示する最大行数。これを超える候補はリスト内でスクロールさせる
    public let maxVisibleRowCount: Int
    /// 最小表示行数。候補 0 件時の案内（UX-001 §5）を出す領域として確保する
    public let minVisibleRowCount: Int
    /// 上部の検索フィールド領域の高さ（区切り線を含む）
    public let searchFieldHeight: CGFloat
    /// 下部のヒント / 状態表示フッターの高さ（区切り線を含む）
    public let footerHeight: CGFloat
    /// パネルの角からパレットの角までの内側方向のオフセット
    public let panelCornerOffset: CGFloat

    public init(
        width: CGFloat,
        rowHeight: CGFloat,
        maxVisibleRowCount: Int,
        minVisibleRowCount: Int,
        searchFieldHeight: CGFloat,
        footerHeight: CGFloat,
        panelCornerOffset: CGFloat
    ) {
        self.width = width
        self.rowHeight = rowHeight
        self.maxVisibleRowCount = maxVisibleRowCount
        self.minVisibleRowCount = minVisibleRowCount
        self.searchFieldHeight = searchFieldHeight
        self.footerHeight = footerHeight
        self.panelCornerOffset = panelCornerOffset
    }

    /// 標準値。幅・行高・最大行数・オフセットは UX-001 §3 の値。
    /// 検索フィールドとフッターの高さは UX-001 に指定がないため仮に決めた値で、ビューの本実装（#21）で調整してよい。
    public static let standard = PaletteMetrics(
        width: 560,
        rowHeight: 28,
        maxVisibleRowCount: 8,
        minVisibleRowCount: 1,
        searchFieldHeight: 44,
        footerHeight: 28,
        panelCornerOffset: 12
    )

    /// 候補数から実際に表示する行数を求める。
    public func visibleRowCount(for rowCount: Int) -> Int {
        min(max(rowCount, minVisibleRowCount), maxVisibleRowCount)
    }

    /// 候補数に応じたパレット全体のサイズ。
    public func size(rowCount: Int) -> CGSize {
        let listHeight = CGFloat(visibleRowCount(for: rowCount)) * rowHeight
        return CGSize(width: width, height: searchFieldHeight + listHeight + footerHeight)
    }
}
