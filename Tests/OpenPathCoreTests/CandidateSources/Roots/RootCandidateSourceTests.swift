import Foundation
import Testing

import OpenPathCore

@Suite("RootCandidateSource")
struct RootCandidateSourceTests {
    private static let smallLimit = 2

    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    @Test("kind はルートのパスを持つ .root")
    func kindIsRoot() {
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions())

        #expect(source.kind == .root(tree.root))
        #expect(source.root == tree.root)
    }

    @Test("snapshot はルートを走査した候補と警告を返す")
    func snapshotScansRoot() async throws {
        try tree.makeDirectories("a", "b")
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions(depth: 1, itemLimit: Self.smallLimit))

        let snapshot = try await source.snapshot()

        #expect(snapshot.items.count == Self.smallLimit)
        #expect(snapshot.warnings == [.rootTruncated(root: tree.root, limit: Self.smallLimit)])
    }

    @Test("設定の roots ごとに、設定の depth / includeFiles / ignore で走査するソースを作る")
    func makesSourcesFromConfig() async throws {
        let second = tree.outsidePath("second")
        try tree.makeDirectories("keep/deep", "skip")
        try tree.makeFiles("note.txt")
        try FileTreeFixture.makeDirectory(atPath: second + "/repo")
        let config = Config(roots: [tree.root, second], depth: 1, includeFiles: true, ignore: ["skip"])

        let sources = RootCandidateSource.sources(for: config)
        try #require(sources.map(\.kind) == [.root(tree.root), .root(second)])
        let first = try await sources[0].snapshot()
        let other = try await sources[1].snapshot()

        #expect(first.itemSet == [.directory(tree.root), .directory(tree.path("keep")), .file(tree.path("note.txt"))])
        #expect(other.itemSet == [.directory(second), .directory(second + "/repo")])
    }

    @Test("roots が空ならソースを作らない")
    func makesNoSourcesWithoutRoots() {
        #expect(RootCandidateSource.sources(for: Config(roots: [])).isEmpty)
    }

    @Test("キャンセルされたタスクから呼ぶと CancellationError を投げる")
    func throwsWhenCancelled() async throws {
        try tree.makeDirectories("a")
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions())

        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await source.snapshot() }
        }
    }
}
