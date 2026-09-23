import Foundation
import Testing

import OpenPathCore

@Suite("RootDirectoryScanner: 深さ・除外・ファイル")
struct RootDirectoryScannerTests {
    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    private func scan(
        root: String? = nil,
        depth: Int = Config.defaultDepth,
        includeFiles: Bool = false,
        ignoredNames: Set<String> = Set(Config.defaultIgnore)
    ) throws -> CandidateSourceSnapshot {
        let options = RootScanOptions(depth: depth, includeFiles: includeFiles, ignoredNames: ignoredNames)
        return try RootDirectoryScanner(options: options).scan(root: root ?? tree.root)
    }

    // MARK: - 深さ

    @Test("depth=2 ではルート自身と 2 階層目までのディレクトリを返し、3 階層目は含めない")
    func excludesThirdLevelWhenDepthIsTwo() throws {
        try tree.makeDirectories("a/b/c/d", "e")

        let snapshot = try scan(depth: 2)

        #expect(snapshot.itemSet == [
            .directory(tree.root), .directory(tree.path("a")), .directory(tree.path("a/b")), .directory(tree.path("e")),
        ])
        #expect(snapshot.items.count == 4)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test(
        "depth までの階層だけを返す（0 はルート自身のみ）",
        arguments: zip([0, 1, 2, 3], [[""], ["", "a"], ["", "a", "a/b"], ["", "a", "a/b", "a/b/c"]])
    )
    func returnsLevelsUpToDepth(depth: Int, expectedRelativePaths: [String]) throws {
        try tree.makeDirectories("a/b/c/d")

        let snapshot = try scan(depth: depth)

        #expect(snapshot.pathSet == Set(expectedRelativePaths.map(tree.path)))
        #expect(snapshot.items.count == expectedRelativePaths.count)
    }

    @Test("負の depth はルート自身のみとして扱う")
    func negativeDepthReturnsRootOnly() throws {
        try tree.makeDirectories("a")

        let snapshot = try scan(depth: -1)

        #expect(snapshot.items == [.directory(tree.root)])
    }

    // MARK: - ignore

    @Test("ignore に一致する名前のディレクトリは、どの階層にあっても配下ごと除外する")
    func excludesIgnoredDirectoriesWithDescendants() throws {
        try tree.makeDirectories("node_modules/pkg", "app/node_modules/lib", "app/src")

        let snapshot = try scan(depth: 3)

        #expect(snapshot.pathSet == [tree.root, tree.path("app"), tree.path("app/src")])
        #expect(!snapshot.items.contains { $0.path.contains("node_modules") })
    }

    @Test("既定の ignore（node_modules / .git / target / DerivedData / .build）はすべて除外する")
    func excludesAllDefaultIgnoredNames() throws {
        for name in Config.defaultIgnore {
            try tree.makeDirectories("repo/\(name)/inner")
        }
        try tree.makeDirectories("repo/Sources")

        let snapshot = try scan(depth: 3, ignoredNames: Set(Config.default.ignore))

        #expect(snapshot.pathSet == [tree.root, tree.path("repo"), tree.path("repo/Sources")])
    }

    @Test("ignore に一致する名前のファイルも含めない")
    func excludesIgnoredFiles() throws {
        try tree.makeFiles("target", "keep.txt")

        let snapshot = try scan(includeFiles: true)

        #expect(snapshot.itemSet == [.directory(tree.root), .file(tree.path("keep.txt"))])
    }

    @Test("ignore はルート自身の名前には適用しない")
    func doesNotApplyIgnoreToRoot() throws {
        try tree.makeDirectories("target/inner")

        let snapshot = try scan(root: tree.path("target"), depth: 1)

        #expect(snapshot.pathSet == [tree.path("target"), tree.path("target/inner")])
    }

    @Test("ignore は名前の完全一致で判定し、部分一致や大文字小文字違いは除外しない")
    func matchesIgnoredNamesExactly() throws {
        try tree.makeDirectories("my_node_modules", "Target", "targets")

        let snapshot = try scan(depth: 1, ignoredNames: ["node_modules", "target"])

        #expect(snapshot.pathSet == [tree.root, tree.path("my_node_modules"), tree.path("Target"), tree.path("targets")])
    }

    // MARK: - 隠しファイル

    @Test("隠しファイルと隠しディレクトリはその配下も含めない")
    func excludesHiddenEntries() throws {
        try tree.makeDirectories(".cache/inner", "visible/.secret")
        try tree.makeFiles(".env", "visible/.hidden-file", "visible/shown.txt")

        let snapshot = try scan(includeFiles: true, ignoredNames: [])

        #expect(snapshot.itemSet == [
            .directory(tree.root), .directory(tree.path("visible")), .file(tree.path("visible/shown.txt")),
        ])
    }

    @Test("隠しディレクトリをルートに指定した場合は、その配下を走査する")
    func scansHiddenRoot() throws {
        try tree.makeDirectories(".config/app")

        let snapshot = try scan(root: tree.path(".config"), depth: 1)

        #expect(snapshot.pathSet == [tree.path(".config"), tree.path(".config/app")])
    }

    // MARK: - includeFiles

    @Test("includeFiles=false ならディレクトリだけを返す")
    func excludesFilesByDefault() throws {
        try tree.makeDirectories("docs")
        try tree.makeFiles("README.md", "docs/guide.md")

        let snapshot = try scan(includeFiles: false)

        #expect(snapshot.itemSet == [.directory(tree.root), .directory(tree.path("docs"))])
    }

    @Test("includeFiles=true なら depth までのファイルを isDirectory=false で含める")
    func includesFilesWithinDepth() throws {
        try tree.makeDirectories("docs/deep")
        try tree.makeFiles("README.md", "docs/guide.md", "docs/deep/too-deep.md")

        let snapshot = try scan(depth: 2, includeFiles: true)

        #expect(snapshot.itemSet == [
            .directory(tree.root), .file(tree.path("README.md")), .directory(tree.path("docs")),
            .file(tree.path("docs/guide.md")), .directory(tree.path("docs/deep")),
        ])
    }

    // MARK: - パスの表記

    @Test("パスは設定したルートの表記を起点にし、/private への解決や末尾の / を含まない")
    func keepsConfiguredRootSpelling() throws {
        try tree.makeDirectories("a/b")

        let snapshot = try scan(depth: 2)

        #expect(tree.root.hasPrefix("/var/"))
        #expect(snapshot.pathSet == [tree.root, tree.path("a"), tree.path("a/b")])
        #expect(snapshot.items.allSatisfy { $0.path.hasPrefix(tree.root) })
        #expect(snapshot.items.allSatisfy { !$0.path.hasSuffix("/") })
    }

    @Test("日本語の名前もそのままのパスで返す")
    func keepsJapaneseNames() throws {
        try tree.makeDirectories("資料/議事録")

        let snapshot = try scan(depth: 2)

        #expect(snapshot.pathSet == [tree.root, tree.path("資料"), tree.path("資料/議事録")])
    }

    @Test("ルートが / のとき、配下のパスは // で始まらない")
    func avoidsDoubleSlashUnderFilesystemRoot() throws {
        let options = RootScanOptions(depth: 1, includeFiles: false, ignoredNames: [], itemLimit: 3)

        let snapshot = try RootDirectoryScanner(options: options).scan(root: "/")

        #expect(snapshot.items.first == .directory("/"))
        #expect(snapshot.items.count == 3)
        #expect(snapshot.items.dropFirst().allSatisfy { $0.path.hasPrefix("/") && !$0.path.hasPrefix("//") })
    }
}
