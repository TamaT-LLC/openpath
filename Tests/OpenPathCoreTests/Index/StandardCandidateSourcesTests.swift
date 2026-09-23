import Testing

import OpenPathCore

/// 設定から組み立てる本番の候補ソース（DSN-002 §3）。
@Suite("StandardCandidateSources")
struct StandardCandidateSourcesTests {
    private static let firstRoot = "/Users/me/repos"
    private static let secondRoot = "/Users/me/Documents"
    private static let searchPath = "/usr/bin:/bin"

    private static func makeSources() -> StandardCandidateSources {
        StandardCandidateSources(
            history: HistoryCandidateSource { [] },
            searchPathProvider: SearchPathProviderSpy(path: searchPath)
        )
    }

    @Test("history・roots（設定の順に 1 ルート 1 ソース）・ghq の順に並べる")
    func buildsHistoryRootsAndGhq() {
        let config = Config(roots: [Self.firstRoot, Self.secondRoot], ghq: GhqConfig(enabled: true))

        let kinds = Self.makeSources().sources(for: config).map(\.kind)

        #expect(kinds == [.history, .root(Self.firstRoot), .root(Self.secondRoot), .ghq])
    }

    @Test("ghq が無効なら ghq のソースを含めない")
    func omitsGhqWhenDisabled() {
        let config = Config(roots: [Self.firstRoot], ghq: GhqConfig(enabled: false))

        let kinds = Self.makeSources().sources(for: config).map(\.kind)

        #expect(kinds == [.history, .root(Self.firstRoot)])
    }

    @Test("roots が空なら history と ghq だけ")
    func buildsWithoutRoots() {
        let config = Config(roots: [], ghq: GhqConfig(enabled: true))

        let kinds = Self.makeSources().sources(for: config).map(\.kind)

        #expect(kinds == [.history, .ghq])
    }

    @Test("roots のソースは設定の depth / include_files / ignore で走査する")
    func rootSourcesUseConfigScanOptions() async throws {
        let tree = try FileTreeFixture()
        try tree.makeDirectories("a/b/c", "node_modules/d")
        try tree.makeFiles("a/file.txt")
        let config = Config(roots: [tree.root], depth: 1, includeFiles: false, ignore: ["node_modules"], ghq: GhqConfig(enabled: false))
        let sources = Self.makeSources().sources(for: config)
        let rootSource = try #require(sources.first { $0.kind == .root(tree.root) })

        let snapshot = try await rootSource.snapshot()

        #expect(snapshot.items.map(\.path).sorted() == [tree.root, tree.path("a")])
    }
}
