import Testing

import OpenPathCore

@Suite("GhqRepositoryLister: 出力の正規化")
struct GhqOutputNormalizationTests {
    private typealias F = GhqFixtures

    private static func listRepositories(rootOutput: String = F.ghqRoot + "\n", listOutput: String) async -> GhqListing {
        let runner = F.makeRunner(rootOutput: rootOutput, listOutput: listOutput)
        return await F.makeLister(runner: runner).listRepositories()
    }

    @Test("空行・行頭行末の空白・CRLF の改行を取り除く")
    func trimsBlankLinesAndWhitespace() async {
        let listing = await Self.listRepositories(listOutput: "\n  /r/a  \r\n\r\n\t/r/b\n   \n")

        #expect(listing == GhqListing(repositoryPaths: ["/r/a", "/r/b"], failure: nil))
    }

    @Test("重複は最初に出現した順序を保って 1 件にまとめる")
    func removesDuplicatesKeepingOrder() async {
        let listing = await Self.listRepositories(listOutput: "/r/b\n/r/a\n/r/b\n/r/a\n/r/c\n")

        #expect(listing.repositoryPaths == ["/r/b", "/r/a", "/r/c"])
    }

    @Test("相対パスは ghq root と結合して絶対パスにする")
    func joinsRelativePathsWithRoot() async {
        let listing = await Self.listRepositories(
            rootOutput: "  \(F.ghqRoot)\n",
            listOutput: "github.com/alice/a\n/abs/b\n"
        )

        #expect(listing.repositoryPaths == ["\(F.ghqRoot)/github.com/alice/a", "/abs/b"])
    }

    @Test("ghq root が末尾スラッシュ付きでも区切りを二重にしない")
    func joinsWithRootHavingTrailingSlash() async {
        let listing = await Self.listRepositories(rootOutput: "\(F.ghqRoot)/\n", listOutput: "github.com/alice/a")

        #expect(listing.repositoryPaths == ["\(F.ghqRoot)/github.com/alice/a"])
    }

    @Test("結合の結果として重複したパスも 1 件にまとめる")
    func removesDuplicatesAfterJoining() async {
        let listing = await Self.listRepositories(listOutput: "github.com/alice/a\n\(F.ghqRoot)/github.com/alice/a\n")

        #expect(listing.repositoryPaths == ["\(F.ghqRoot)/github.com/alice/a"])
    }

    @Test("ghq list -p の出力が空なら失敗扱いにせず空を返す")
    func emptyListIsNotFailure() async {
        let listing = await Self.listRepositories(listOutput: "")

        #expect(listing == GhqListing(repositoryPaths: [], failure: nil))
    }
}
