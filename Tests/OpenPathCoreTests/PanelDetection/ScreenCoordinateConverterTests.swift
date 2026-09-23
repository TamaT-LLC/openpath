import CoreGraphics
import Testing

import OpenPathCore

/// ディスプレイの配置。同じディスプレイを AX（CGDisplayBounds）と NSScreen（NSScreen.frame）の両方の座標で持つ。
/// 期待値の NSScreen 側は、変換式を使わずに配置から手で求めた値。
struct DisplayLayout: CustomTestStringConvertible, Sendable {
    struct Display: Sendable {
        let axBounds: CGRect
        let screenFrame: CGRect
    }

    let name: String
    /// 先頭がプライマリディスプレイ（メニューバーのある画面）
    let displays: [Display]

    var testDescription: String {
        name
    }

    var converter: ScreenCoordinateConverter {
        ScreenCoordinateConverter(primaryScreenHeight: displays[0].axBounds.height)
    }

    var screenFrames: [CGRect] {
        displays.map(\.screenFrame)
    }

    static let all: [DisplayLayout] = [
        DisplayLayout(name: "プライマリのみ", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        ]),
        // この開発機の実際の配置（上端揃えで右に同じ大きさ）
        DisplayLayout(name: "右に同じ大きさ", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            Display(
                axBounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                screenFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
            ),
        ]),
        // 左に小さい画面を上端揃えで置くと、NSScreen では下端が 1080 - 900 = 180 だけ上がる
        DisplayLayout(name: "左に小さい画面（上端揃え）", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            Display(
                axBounds: CGRect(x: -1440, y: 0, width: 1440, height: 900),
                screenFrame: CGRect(x: -1440, y: 180, width: 1440, height: 900)
            ),
        ]),
        // Retina の内蔵画面（1512x982 ポイント、倍率 2）の上に、非 Retina の外部画面（2560x1440、倍率 1）
        DisplayLayout(name: "上に外部画面（Retina 混在）", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 1512, height: 982), screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            Display(
                axBounds: CGRect(x: -524, y: -1440, width: 2560, height: 1440),
                screenFrame: CGRect(x: -524, y: 982, width: 2560, height: 1440)
            ),
        ]),
        DisplayLayout(name: "下に外部画面", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440), screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440)),
            Display(
                axBounds: CGRect(x: 320, y: 1440, width: 1920, height: 1080),
                screenFrame: CGRect(x: 320, y: -1080, width: 1920, height: 1080)
            ),
        ]),
        // 右に小さい画面を下端揃えで置くと、AX では上端が 1440 - 1080 = 360 だけ下がる
        DisplayLayout(name: "右に小さい画面（下端揃え）", displays: [
            Display(axBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440), screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440)),
            Display(
                axBounds: CGRect(x: 2560, y: 360, width: 1920, height: 1080),
                screenFrame: CGRect(x: 2560, y: 0, width: 1920, height: 1080)
            ),
        ]),
    ]
}

@Suite("ScreenCoordinateConverter（AX 座標 → NSScreen 座標）")
struct ScreenCoordinateConverterTests {
    private static let primaryHeight: CGFloat = 1080
    private static let converter = ScreenCoordinateConverter(primaryScreenHeight: primaryHeight)

    @Test("プライマリ画面の左上原点・y 下向きの矩形を、左下原点・y 上向きに変換する（x と大きさは変えない）")
    func flipsYAroundPrimaryScreen() {
        let axRect = CGRect(x: 100, y: 120, width: 800, height: 520)

        // 上端は AX で 120 下がった位置 → NSScreen で 1080 - 120 = 960。下端は 960 - 520 = 440
        #expect(Self.converter.screenRect(fromAXRect: axRect) == CGRect(x: 100, y: 440, width: 800, height: 520))
    }

    @Test("画面の上端に接するパネルは、NSScreen では上端が画面の高さになる")
    func topEdge() {
        let axRect = CGRect(x: 0, y: 0, width: 400, height: 300)

        let screenRect = Self.converter.screenRect(fromAXRect: axRect)

        #expect(screenRect.maxY == Self.primaryHeight)
        #expect(screenRect.minY == 780)
    }

    @Test("画面の下端に接するパネルは、NSScreen では下端が 0 になる")
    func bottomEdge() {
        let axRect = CGRect(x: 10, y: 780, width: 400, height: 300)

        #expect(Self.converter.screenRect(fromAXRect: axRect).minY == 0)
    }

    @Test("矩形を読めなかったパネル（.zero）は、プライマリ画面の左上の点になる")
    func zeroRect() {
        #expect(Self.converter.screenRect(fromAXRect: .zero) == CGRect(x: 0, y: Self.primaryHeight, width: 0, height: 0))
    }

    // MARK: - マルチディスプレイ

    @Test("どのディスプレイの矩形も、プライマリの高さだけで NSScreen の矩形に変換できる", arguments: DisplayLayout.all)
    func displayBoundsMapToScreenFrames(layout: DisplayLayout) {
        for display in layout.displays {
            #expect(layout.converter.screenRect(fromAXRect: display.axBounds) == display.screenFrame)
        }
    }

    @Test("メイン以外のディスプレイのパネルも、そのディスプレイの中に変換され、配置先の画面に選ばれる", arguments: DisplayLayout.all)
    func panelOnEachDisplay(layout: DisplayLayout) throws {
        for (index, display) in layout.displays.enumerated() {
            // ディスプレイの左上から (100, 80) の位置にあるパネル
            let axPanel = CGRect(x: display.axBounds.minX + 100, y: display.axBounds.minY + 80, width: 800, height: 500)

            let screenPanel = layout.converter.screenRect(fromAXRect: axPanel)

            #expect(display.screenFrame.contains(screenPanel))
            #expect(screenPanel.minX == display.screenFrame.minX + 100)
            #expect(screenPanel.maxY == display.screenFrame.maxY - 80)
            #expect(PalettePlacement.screenIndex(for: screenPanel, screenFrames: layout.screenFrames) == index)
        }
    }

    @Test("変換した矩形を PalettePlacement に渡すと、パレットはそのディスプレイのパネル右上に出る", arguments: DisplayLayout.all)
    func paletteIsPlacedAtPanelTopRight(layout: DisplayLayout) throws {
        let metrics = PaletteMetrics.standard
        for display in layout.displays {
            let axPanel = CGRect(x: display.axBounds.minX + 200, y: display.axBounds.minY + 100, width: 880, height: 448)
            let screenPanel = layout.converter.screenRect(fromAXRect: axPanel)

            let palette = PalettePlacement.frame(
                panelFrame: screenPanel,
                visibleScreenFrame: display.screenFrame,
                rowCount: 3,
                metrics: metrics
            )

            #expect(palette.maxX == screenPanel.maxX - metrics.panelCornerOffset)
            #expect(palette.maxY == screenPanel.maxY - metrics.panelCornerOffset)
            #expect(display.screenFrame.contains(palette))
        }
    }

    @Test("2 つのディスプレイにまたがるパネルは、広く重なる方の画面に配置する")
    func panelSpanningTwoDisplays() throws {
        let layout = try #require(DisplayLayout.all.first { $0.name == "右に同じ大きさ" })
        // プライマリに 300、右の画面に 500 はみ出したパネル
        let axPanel = CGRect(x: 1620, y: 200, width: 800, height: 500)

        let screenPanel = layout.converter.screenRect(fromAXRect: axPanel)

        #expect(screenPanel == CGRect(x: 1620, y: 380, width: 800, height: 500))
        #expect(PalettePlacement.screenIndex(for: screenPanel, screenFrames: layout.screenFrames) == 1)
    }
}
