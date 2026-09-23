import Foundation
import Testing

import OpenPathCore

@Suite("DirectPathEntry")
struct DirectPathEntryTests {
    private let tree: FileTreeFixture
    /// `~` をフィクスチャのルートに展開する
    private let entry: DirectPathEntry

    init() throws {
        tree = try FileTreeFixture()
        try tree.makeDirectories("repos/fern", "repos/資料")
        try tree.makeFiles("repos/notes.txt")
        entry = DirectPathEntry(homeDirectory: tree.root)
    }

    // MARK: - 行を作る条件

    @Test("絶対パスで既存のディレクトリを打つと、その場所の行を作る")
    func absoluteDirectory() {
        let row = entry.row(for: tree.path("repos/fern"), directoriesOnly: true)

        #expect(row == PaletteRow(name: "fern", path: tree.path("repos/fern"), lastUsed: nil))
    }

    @Test("~/ で始まるパスはホームディレクトリで展開する")
    func homeRelativePath() {
        let row = entry.row(for: "~/repos/fern", directoriesOnly: true)

        #expect(row?.path == tree.path("repos/fern"))
    }

    @Test("日本語の名前のディレクトリも行にする")
    func japaneseDirectory() {
        let row = entry.row(for: "~/repos/資料", directoriesOnly: true)

        #expect(row?.name == "資料")
    }

    @Test("`.`・`..`・重ねた `/` は字句的に正規化する")
    func normalizesPath() {
        let row = entry.row(for: "~/repos//./fern/../fern", directoriesOnly: true)

        #expect(row?.path == tree.path("repos/fern"))
    }

    @Test(
        "パスとして読めない検索語や、末尾が / の検索語（配下を掘る）では行を作らない",
        arguments: ["fern", "repos/fern", "~", "~repos/fern", "", "~/repos/fern/", "/"]
    )
    func notAPath(query: String) {
        #expect(entry.row(for: query, directoriesOnly: false) == nil)
    }

    @Test("存在しないパスでは行を作らない")
    func missingPath() {
        #expect(entry.row(for: "~/repos/missing", directoriesOnly: false) == nil)
    }

    @Test("ファイルはディレクトリに絞るときは行にせず、ファイルも選べるときは行にする")
    func fileFollowsDirectoriesOnly() {
        #expect(entry.row(for: "~/repos/notes.txt", directoriesOnly: true) == nil)
        #expect(entry.row(for: "~/repos/notes.txt", directoriesOnly: false)?.name == "notes.txt")
    }

    // MARK: - 候補との統合

    @Test("直接入力の行を先頭に置き、同じパスの候補は除いて、その最終使用日時を引き継ぐ")
    func mergesAheadOfCandidates() {
        let lastUsed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let fern = PaletteRow(name: "fern", path: tree.path("repos/fern"), lastUsed: lastUsed, pathHighlights: [0])
        let other = PaletteRow(name: "fern-docs", path: tree.path("repos/fern-docs"), lastUsed: nil)

        let rows = entry.merging([other, fern], query: "~/repos/fern", directoriesOnly: true, limit: 50)

        #expect(rows == [PaletteRow(name: "fern", path: tree.path("repos/fern"), lastUsed: lastUsed), other])
    }

    @Test("直接入力の行を加えても件数の上限に収める")
    func respectsLimit() {
        let candidates = (0..<3).map { PaletteRow(name: "c\($0)", path: tree.path("c\($0)"), lastUsed: nil) }

        let rows = entry.merging(candidates, query: "~/repos/fern", directoriesOnly: true, limit: 3)

        #expect(rows.map(\.name) == ["fern", "c0", "c1"])
    }

    @Test("検索語がパスでなければ候補をそのまま返す")
    func keepsCandidatesForNonPathQuery() {
        let candidates = [PaletteRow(name: "fern", path: tree.path("repos/fern"), lastUsed: nil)]

        #expect(entry.merging(candidates, query: "fern", directoriesOnly: true, limit: 50) == candidates)
        #expect(entry.merging(candidates, query: "~/repos/missing", directoriesOnly: true, limit: 50) == candidates)
    }
}
