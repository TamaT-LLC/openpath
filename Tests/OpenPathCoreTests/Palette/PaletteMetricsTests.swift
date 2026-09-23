import CoreGraphics
import Testing

import OpenPathCore

@Suite("PaletteMetrics")
struct PaletteMetricsTests {
    private let metrics = PaletteMetrics.standard

    @Test("標準値は UX-001 §3 のレイアウト（幅 560pt / 行高 28pt / 最大 8 行 / 12pt オフセット）")
    func standardValuesFollowUXDesign() {
        #expect(metrics.width == 560)
        #expect(metrics.rowHeight == 28)
        #expect(metrics.maxVisibleRowCount == 8)
        #expect(metrics.panelCornerOffset == 12)
    }

    @Test(
        "表示行数は最小 1 行・最大 8 行に丸められる",
        arguments: [
            (rowCount: -1, expected: 1),
            (rowCount: 0, expected: 1),
            (rowCount: 1, expected: 1),
            (rowCount: 3, expected: 3),
            (rowCount: 8, expected: 8),
            (rowCount: 9, expected: 8),
            (rowCount: 100, expected: 8),
        ]
    )
    func visibleRowCountIsClamped(rowCount: Int, expected: Int) {
        #expect(metrics.visibleRowCount(for: rowCount) == expected)
    }

    @Test(
        "高さは 検索フィールド + 表示行数 × 行高 + フッター",
        arguments: [0, 1, 3, 8, 20]
    )
    func heightIsSumOfSections(rowCount: Int) {
        let size = metrics.size(rowCount: rowCount)
        let visibleRowCount = CGFloat(metrics.visibleRowCount(for: rowCount))
        let expectedHeight = metrics.searchFieldHeight + visibleRowCount * metrics.rowHeight + metrics.footerHeight

        #expect(size.width == metrics.width)
        #expect(size.height == expectedHeight)
    }

    @Test("行数が増えるほど高くなり、最大行数で頭打ちになる")
    func heightGrowsWithRowCountUntilMax() {
        let oneRow = metrics.size(rowCount: 1).height
        let threeRows = metrics.size(rowCount: 3).height
        let maxRows = metrics.size(rowCount: metrics.maxVisibleRowCount).height
        let overMaxRows = metrics.size(rowCount: metrics.maxVisibleRowCount + 1).height

        #expect(threeRows - oneRow == 2 * metrics.rowHeight)
        #expect(maxRows > threeRows)
        #expect(overMaxRows == maxRows)
    }
}
