import Testing

import OpenPathCore

@Suite("PaletteRowPresentation")
struct PaletteRowPresentationTests {
    private static let home = "/Users/example"

    @Test("表示名はそのまま、場所は親ディレクトリをホーム短縮・中央省略した候補になる")
    func presentsNameAndParentDirectory() {
        let row = PaletteRow(name: "fern", path: "/Users/example/repos/github.com/TamaT-LLC/fern", lastUsed: nil)

        let presentation = PaletteRowPresentation(row: row, homeDirectory: Self.home)

        #expect(presentation.name == HighlightedText("fern"))
        #expect(presentation.locationVariants.map(\.text) == [
            "~/repos/github.com/TamaT-LLC",
            "~/repos/…/TamaT-LLC",
            "~/…/TamaT-LLC",
        ])
    }

    @Test("表示名のマッチ位置をそのままハイライトする")
    func highlightsNameMatches() {
        let row = PaletteRow(
            name: "fern-docs",
            path: "/Users/example/repos/fern-docs",
            lastUsed: nil,
            nameHighlights: [0, 1, 2, 3]
        )

        let presentation = PaletteRowPresentation(row: row, homeDirectory: Self.home)

        #expect(presentation.name.highlightedOffsets == [0, 1, 2, 3])
        #expect(presentation.locationVariants.map(\.highlightedOffsets) == [[]])
    }

    @Test("パスのマッチ位置のうち、末尾要素の分は表示名へ、親ディレクトリの分は場所へ移す")
    func distributesPathMatchesToNameAndLocation() {
        // "/Users/example/repos/" は 21 文字。r(15) と fern の f, e(21, 22) にマッチした場合
        let row = PaletteRow(
            name: "fern",
            path: "/Users/example/repos/fern",
            lastUsed: nil,
            pathHighlights: [15, 21, 22]
        )

        let presentation = PaletteRowPresentation(row: row, homeDirectory: Self.home)

        #expect(presentation.name == HighlightedText("fern", highlightedOffsets: [0, 1]))
        #expect(presentation.locationVariants == [HighlightedText("~/repos", highlightedOffsets: [2])])
    }

    @Test("表示名とパスの末尾要素が異なる場合は、末尾要素のマッチ位置を表示名へ移さない")
    func doesNotTransferWhenNameDiffers() {
        let row = PaletteRow(
            name: "別名",
            path: "/Users/example/repos/fern",
            lastUsed: nil,
            pathHighlights: [21]
        )

        let presentation = PaletteRowPresentation(row: row, homeDirectory: Self.home)

        #expect(presentation.name.highlightedOffsets.isEmpty)
    }

    @Test("日本語のパスも表示名と場所に分けてハイライトできる")
    func presentsJapanesePath() {
        // "/Users/example/" は 15 文字。書(15) と プ(18) にマッチした場合
        let row = PaletteRow(
            name: "プロジェクト",
            path: "/Users/example/書類/プロジェクト",
            lastUsed: nil,
            pathHighlights: [15, 18]
        )

        let presentation = PaletteRowPresentation(row: row, homeDirectory: Self.home)

        #expect(presentation.name == HighlightedText("プロジェクト", highlightedOffsets: [0]))
        #expect(presentation.locationVariants == [HighlightedText("~/書類", highlightedOffsets: [2])])
    }

    @Test("行の識別子はパス")
    func rowIdentifierIsPath() {
        let row = PaletteRow(name: "fern", path: "/Users/example/repos/fern", lastUsed: nil)

        #expect(row.id == "/Users/example/repos/fern")
    }
}
