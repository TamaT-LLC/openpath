import CoreGraphics
import Testing

import OpenPathCore

/// 座標はすべて NSScreen 座標系（左下原点、y は上向き）。
/// 標準メトリクスでは 幅 560pt、8 行時の高さ 296pt（44 + 8 × 28 + 28）。
@Suite("PalettePlacement")
struct PalettePlacementTests {
    /// 1920×1080 の画面で、下に Dock（70pt）、上にメニューバー（25pt）がある想定の可視領域。
    private static let visibleScreenFrame = CGRect(x: 0, y: 70, width: 1920, height: 985)
    private static let maxRowCount = 8
    private static let paletteWidth: CGFloat = 560
    private static let maxRowsHeight: CGFloat = 296
    private static let twoRowsHeight: CGFloat = 128 // 44 + 2 × 28 + 28
    private static let oneRowHeight: CGFloat = 100 // 44 + 1 × 28 + 28

    private static func frame(panel panelFrame: CGRect, rowCount: Int = maxRowCount) -> CGRect {
        PalettePlacement.frame(panelFrame: panelFrame, visibleScreenFrame: visibleScreenFrame, rowCount: rowCount)
    }

    // MARK: - 配置

    @Test("通常はパネル右上角から内側へ 12pt ずらして重ねる")
    func placesAtTopRightOfPanel() {
        // パネル右上角 = (1200, 800)
        let panel = CGRect(x: 400, y: 300, width: 800, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 628, y: 492, width: Self.paletteWidth, height: Self.maxRowsHeight))
        #expect(frame.maxX == panel.maxX - 12)
        #expect(frame.maxY == panel.maxY - 12)
    }

    @Test("パネルが画面右端からはみ出し右上に収まらない場合は左上に配置する")
    func placesAtTopLeftWhenRightSideDoesNotFit() {
        // 右上配置だと maxX = 1988 となり可視領域（maxX = 1920）を越える
        let panel = CGRect(x: 1200, y: 300, width: 800, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 1212, y: 492, width: Self.paletteWidth, height: Self.maxRowsHeight))
        #expect(frame.minX == panel.minX + 12)
    }

    @Test("右上配置の右端が画面右端ちょうどなら右上のまま")
    func keepsTopRightWhenExactlyFits() {
        // 右上配置の maxX = 1932 - 12 = 1920（可視領域の右端と一致）
        let panel = CGRect(x: 1132, y: 300, width: 800, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 1360, y: 492, width: Self.paletteWidth, height: Self.maxRowsHeight))
    }

    @Test("左上配置でも右端からはみ出す場合は画面右端に寄せる")
    func clampsToRightEdgeWhenTopLeftAlsoOverflows() {
        let panel = CGRect(x: 1500, y: 300, width: 800, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 1360, y: 492, width: Self.paletteWidth, height: Self.maxRowsHeight))
    }

    // MARK: - クランプ

    @Test("パネル上端が可視領域より上にある場合は上端にクランプする")
    func clampsToTopEdge() {
        // パネル上端 1200 は可視領域の上端 1055 を越える
        let panel = CGRect(x: 400, y: 700, width: 800, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 628, y: 759, width: Self.paletteWidth, height: Self.maxRowsHeight))
        #expect(frame.maxY == Self.visibleScreenFrame.maxY)
    }

    @Test("パネルが画面下端に近く下にはみ出す場合は下端にクランプする")
    func clampsToBottomEdge() {
        // 配置すると minY = 330 - 12 - 296 = 22 となり、可視領域の下端 70 を下回る
        let panel = CGRect(x: 400, y: 80, width: 800, height: 250)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 628, y: 70, width: Self.paletteWidth, height: Self.maxRowsHeight))
        #expect(frame.minY == Self.visibleScreenFrame.minY)
    }

    @Test("パネルがパレットより狭く左端にある場合は左端にクランプする")
    func clampsToLeftEdge() {
        let panel = CGRect(x: 0, y: 300, width: 400, height: 500)

        let frame = Self.frame(panel: panel)

        #expect(frame == CGRect(x: 0, y: 492, width: Self.paletteWidth, height: Self.maxRowsHeight))
    }

    @Test("パレットが可視領域より大きい場合は検索フィールドのある左上を優先して見せる")
    func prefersTopLeftWhenLargerThanScreen() {
        let tinyScreen = CGRect(x: 0, y: 0, width: 400, height: 200)

        let frame = PalettePlacement.frame(panelFrame: tinyScreen, visibleScreenFrame: tinyScreen, rowCount: Self.maxRowCount)

        #expect(frame.minX == tinyScreen.minX)
        #expect(frame.maxY == tinyScreen.maxY)
    }

    @Test("原点が負のサブディスプレイでも可視領域を基準に配置する")
    func handlesSecondaryScreenWithNegativeOrigin() {
        // メインディスプレイの左に置いたサブディスプレイ（maxX = 0, maxY = 1075）
        let secondaryScreen = CGRect(x: -1440, y: 200, width: 1440, height: 875)
        let panel = CGRect(x: -900, y: 400, width: 900, height: 600)

        let frame = PalettePlacement.frame(panelFrame: panel, visibleScreenFrame: secondaryScreen, rowCount: Self.maxRowCount)

        #expect(frame == CGRect(x: -572, y: 692, width: Self.paletteWidth, height: Self.maxRowsHeight))
    }

    @Test(
        "どこにパネルがあってもパレットは可視領域内に収まる",
        arguments: [
            CGRect(x: 400, y: 300, width: 800, height: 500),
            CGRect(x: -500, y: 300, width: 800, height: 500),
            CGRect(x: 1700, y: 300, width: 800, height: 500),
            CGRect(x: 400, y: -400, width: 800, height: 500),
            CGRect(x: 400, y: 900, width: 800, height: 500),
            CGRect(x: 1800, y: 1000, width: 300, height: 200),
            CGRect(x: -800, y: -600, width: 300, height: 200),
        ]
    )
    func alwaysStaysInsideVisibleScreenFrame(panel: CGRect) {
        let frame = Self.frame(panel: panel)

        #expect(Self.visibleScreenFrame.contains(frame))
    }

    // MARK: - 行数

    @Test("行数に応じて高さが変わり、上端（検索フィールドの位置）は動かない")
    func heightDependsOnRowCountWithFixedTop() {
        let panel = CGRect(x: 400, y: 300, width: 800, height: 500)

        let twoRows = Self.frame(panel: panel, rowCount: 2)
        let eightRows = Self.frame(panel: panel, rowCount: 8)
        let twentyRows = Self.frame(panel: panel, rowCount: 20)

        #expect(twoRows.height == Self.twoRowsHeight)
        #expect(eightRows.height == Self.maxRowsHeight)
        #expect(twentyRows.height == Self.maxRowsHeight)
        #expect(twoRows.maxY == eightRows.maxY)
    }

    @Test("候補 0 件でも案内表示用に 1 行分の高さを確保する")
    func reservesOneRowWhenEmpty() {
        let panel = CGRect(x: 400, y: 300, width: 800, height: 500)

        let frame = Self.frame(panel: panel, rowCount: 0)

        #expect(frame.height == Self.oneRowHeight)
    }

    // MARK: - 画面の選択

    private static let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private static let rightScreen = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    @Test("画面がない場合は nil")
    func screenIndexIsNilWithoutScreens() {
        let panel = CGRect(x: 400, y: 300, width: 800, height: 500)

        #expect(PalettePlacement.screenIndex(for: panel, screenFrames: []) == nil)
    }

    @Test("パネルと最も広く重なる画面を選ぶ")
    func screenIndexPicksLargestIntersection() {
        // メイン画面と 220pt 幅、右画面と 580pt 幅で重なる
        let panel = CGRect(x: 1700, y: 300, width: 800, height: 500)

        #expect(PalettePlacement.screenIndex(for: panel, screenFrames: [Self.mainScreen, Self.rightScreen]) == 1)
    }

    @Test("どの画面とも重ならない場合は中心が最も近い画面を選ぶ")
    func screenIndexFallsBackToNearestScreen() {
        let farLeftPanel = CGRect(x: -3000, y: 300, width: 800, height: 500)
        let farRightPanel = CGRect(x: 6000, y: 300, width: 800, height: 500)
        let screens = [Self.mainScreen, Self.rightScreen]

        #expect(PalettePlacement.screenIndex(for: farLeftPanel, screenFrames: screens) == 0)
        #expect(PalettePlacement.screenIndex(for: farRightPanel, screenFrames: screens) == 1)
    }
}
