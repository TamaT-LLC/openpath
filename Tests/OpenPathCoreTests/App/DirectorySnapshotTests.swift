import Foundation
import Testing
import OpenPathCore

@Suite("DirectorySnapshot", .timeLimit(.minutes(1)))
struct DirectorySnapshotTests {
    private let tree: FileTreeFixture

    init() throws { tree = try FileTreeFixture() }

    private func load(_ relativePath: String = "", ignoredNames: Set<String> = Set(Config.defaultIgnore)) async throws -> DirectorySnapshot {
        try await DirectorySnapshot.load(directory: tree.path(relativePath), ignoredNames: ignoredNames)
    }

    @Test("直下のみを列挙し、事前走査の depth に関わらず次の階層へ進める")
    func immediateChildrenBeyondIndexedDepth() async throws {
        try tree.makeDirectories("a/b/c/d", "a/b/other")
        let indexed = try RootDirectoryScanner(options: .init(depth: 2)).scan(root: tree.root)
        #expect(!indexed.pathSet.contains(tree.path("a/b/c")))
        let children = try await load("a/b").search("", directoriesOnly: true, limit: 50)
        #expect(children.rows.map(\.path) == [tree.path("a/b/c"), tree.path("a/b/other")])
        let grandchildren = try await load("a/b/c").search("", directoriesOnly: true, limit: 50)
        #expect(grandchildren.rows.map(\.path) == [tree.path("a/b/c/d")])
    }

    @Test("隠し・ignore を除外し、パッケージをファイルとして扱う")
    func respectsScannerPolicy() async throws {
        try tree.makeDirectories("shown", ".hidden/child", "node_modules/pkg", "Library/child", "Sample.app/Contents")
        try tree.setHiddenFlag("Library")
        try tree.makeFiles("readme.txt")
        let snapshot = try await load()
        let all = try await snapshot.search("", directoriesOnly: false, limit: 50)
        #expect(Set(all.rows.map(\.name)) == ["shown", "Sample.app", "readme.txt"])
        #expect(all.rows.first { $0.name == "Sample.app" }?.isDirectory == false)
        let folders = try await snapshot.search("", directoriesOnly: true, limit: 50)
        #expect(folders.rows.map(\.name) == ["shown"])
    }

    @Test("明示的に開いた隠し・ignore 対象のフォルダ自身には除外を適用しない")
    func explicitDirectoriesCanBeOpened() async throws {
        try tree.makeDirectories(".hidden/child", "node_modules/pkg")
        for path in [".hidden", "node_modules"] {
            let result = try await load(path).search("", directoriesOnly: true, limit: 50)
            #expect(result.rows.count == 1)
        }
    }

    @Test("リンクは直下の候補に留め、明示的に開いたときだけリンク先の直下を読む")
    func symbolicLinksRequireExplicitExpansion() async throws {
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("child/deep"))
        try tree.makeSymbolicLink("link", to: tree.outside)
        try tree.makeSymbolicLink("broken", to: tree.outsidePath("missing"))
        try tree.makeSymbolicLink("loop", to: tree.root)
        let result = try await load().search("", directoriesOnly: true, limit: 50)
        #expect(Set(result.rows.map(\.name)) == ["link", "loop"])
        let linked = try await load("link").search("", directoriesOnly: true, limit: 50)
        #expect(linked.rows.map(\.path) == [tree.path("link/child")])
    }

    @Test("名前だけを検索し、親パスの文字列では一致しない。日本語の一致をハイライトする")
    func matchesOnlyNames() async throws {
        try tree.makeDirectories("uniqueparent/資料", "uniqueparent/other")
        let snapshot = try await load("uniqueparent")
        #expect(try await snapshot.search("uniqueparent", directoriesOnly: true, limit: 50).rows.isEmpty)
        let result = try await snapshot.search("資料", directoriesOnly: true, limit: 50)
        #expect(result.rows.map(\.name) == ["資料"])
        #expect(result.rows.first?.nameHighlights == [0, 1])
    }

    @Test("空・不存在・ファイル・権限不足を別の案内にする")
    func reportsDistinctStates() async throws {
        try tree.makeDirectories("empty", "denied")
        try tree.makeFiles("file.txt")
        try FileTreeFixture.setPermissions(0, atPath: tree.path("denied"))
        defer { try? FileTreeFixture.setPermissions(FileTreeFixture.ownerAllPermissions, atPath: tree.path("denied")) }
        for (path, message) in [
            ("empty", PaletteText.emptyDirectory), ("missing", PaletteText.directoryNotFound),
            ("file.txt", PaletteText.directoryNotDirectory), ("denied", PaletteText.directoryUnreadable),
        ] {
            let result = try await load(path).search("", directoriesOnly: true, limit: 50)
            #expect(result.rows.isEmpty)
            #expect(result.message == message)
        }
    }

    @Test("重複・削除済み候補を除外し、表示件数を制限する")
    func deduplicatesAndChecksExistence() async throws {
        try tree.makeDirectories("a", "b", "c")
        let snapshot = DirectorySnapshot(items: [
            .directory(tree.path("a")), .directory(tree.path("a")),
            .directory(tree.path("b")), .directory(tree.path("c")),
        ])
        try FileManager.default.removeItem(atPath: tree.path("a"))
        let result = try await snapshot.search("", directoriesOnly: true, limit: 1)
        #expect(result.rows.map(\.name) == ["b"])
    }

    @Test("キャンセル済みの列挙は結果を返さない")
    func cancelledLoad() async throws {
        let root = tree.root
        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await DirectorySnapshot.load(directory: root, ignoredNames: []) }
        }
    }

    @Test("動的候補も履歴で順位付けし、最終使用日時を表示する")
    func preservesFrecencyAndLastUsed() async throws {
        try tree.makeDirectories("alpha", "beta")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let history = [HistoryEntry(path: tree.path("beta"), count: 10, lastUsed: now)]
        let snapshot = try await load()
        let result = try await snapshot.search("", directoriesOnly: true, limit: 50, history: history, now: now)
        #expect(result.rows.map(\.name) == ["beta", "alpha"])
        #expect(result.rows.first?.lastUsed == now)
        let cleared = try await snapshot.search("", directoriesOnly: true, limit: 50, history: [], now: now)
        #expect(cleared.rows.map(\.name) == ["alpha", "beta"])
        #expect(cleared.rows.allSatisfy { $0.lastUsed == nil })
    }
}
