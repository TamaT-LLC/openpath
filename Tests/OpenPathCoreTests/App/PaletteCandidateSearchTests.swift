import Foundation
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

    @Test("~/ と字句正規化した直接入力でも、ファジー結果にないお気に入りの別名と履歴を表示する")
    func preservesFavoriteAliasOutsideFuzzyResults() async throws {
        let path = tree.path("Documents/資料")
        let usedAt = IndexFixtures.now
        let index = IndexFixtures.makeIndex(history: [.init(path: path, count: 2, lastUsed: usedAt)])
        await index.replace(source: .favorites, with: [SourceItem(path: path, isDirectory: true, displayName: "仕事")])
        let search = PaletteCandidateSearch.make(index: index, directPath: DirectPathEntry(homeDirectory: tree.root))
        for query in ["~/Documents/資料", "~/Documents/../Documents/資料"] {
            #expect(try await index.query(query, directoriesOnly: true, limit: 50).isEmpty)
            let rows = try await search(query, true, 50)
            #expect(rows.count == 1)
            #expect(rows.first?.name == "仕事")
            #expect(rows.first?.path == path)
            #expect(rows.first?.lastUsed == usedAt)
        }
    }

    @Test("直接入力の別名補完でも、ファイルのフォルダ専用制限と不存在の除外を守る")
    func exactAliasMetadataDoesNotBypassPathValidation() async throws {
        try tree.makeFiles("notes.txt")
        let path = tree.path("notes.txt")
        let index = IndexFixtures.makeIndex()
        await index.replace(source: .favorites, with: [SourceItem(path: path, isDirectory: false, displayName: "メモ")])
        let search = PaletteCandidateSearch.make(index: index, directPath: DirectPathEntry(homeDirectory: tree.root))
        #expect(try await search("~/notes.txt", true, 50).isEmpty)
        #expect(try await search("~/notes.txt", false, 50).first?.name == "メモ")
        try FileManager.default.removeItem(atPath: path)
        #expect(try await search("~/notes.txt", false, 50).isEmpty)
    }
}
