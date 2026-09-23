import Testing

import OpenPathCore

@Suite("PaletteCandidateSearch")
struct PaletteCandidateSearchTests {
    private let tree: FileTreeFixture
    private let search: PaletteQuerySession.Search

    init() async throws {
        tree = try FileTreeFixture()
        try tree.makeDirectories("repos/fern", "repos/fern-docs", "Documents/資料")
        let index = IndexFixtures.makeIndex()
        await index.replace(source: .root(tree.path("repos")), with: [
            IndexFixtures.directory(tree.path("repos/fern")),
            IndexFixtures.directory(tree.path("repos/fern-docs")),
        ])
        search = PaletteCandidateSearch.make(index: index, directPath: DirectPathEntry(homeDirectory: tree.root))
    }

    @Test("候補インデックスの結果をパレットの行にする")
    func returnsIndexRows() async throws {
        let rows = try await search("fern", true, IndexFixtures.generousLimit)

        #expect(rows.map(\.path) == [tree.path("repos/fern"), tree.path("repos/fern-docs")])
        #expect(rows.first?.nameHighlights.isEmpty == false)
    }

    @Test("候補に無い場所でも、存在するパスを打てば先頭に出る")
    func addsDirectPathRow() async throws {
        let rows = try await search("~/Documents/資料", true, IndexFixtures.generousLimit)

        #expect(rows.map(\.path) == [tree.path("Documents/資料")])
    }

    @Test("候補にある場所のパスを打つと、その候補を先頭の 1 行にまとめる")
    func deduplicatesDirectPathRow() async throws {
        let rows = try await search(tree.path("repos/fern"), true, IndexFixtures.generousLimit)

        #expect(rows.first?.path == tree.path("repos/fern"))
        #expect(rows.filter { $0.path == tree.path("repos/fern") }.count == 1)
    }
}
