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

    // MARK: - 変更の検知（Issue #78）

    @Test("trackedSnapshot は snapshot と同じ候補に、変更を確かめる記録を添えて返す")
    func trackedSnapshotReturnsMarker() async throws {
        try tree.makeDirectories("a/b", "c")
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions(depth: 2))

        let tracked = try await source.trackedSnapshot()
        let plain = try await source.snapshot()

        #expect(tracked.snapshot.itemSet == plain.itemSet)
        #expect(tracked.marker != nil)
    }

    @Test("hasChanged は記録の後の変化を確かめる")
    func hasChangedChecksMarker() async throws {
        try tree.makeDirectories("a/b")
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions(depth: 2))
        let marker = try #require(try await source.trackedSnapshot().marker)
        #expect(await !source.hasChanged(since: marker))

        try tree.makeDirectories("a/new")

        #expect(await source.hasChanged(since: marker))
    }

    @Test("別のルート・別の走査条件で作った記録は、変わったものとして扱う")
    func markerFromOtherSourceIsTreatedAsChanged() async throws {
        let other = tree.outsidePath("other")
        try tree.makeDirectories("a")
        try FileTreeFixture.makeDirectory(atPath: other)
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions(depth: 2))
        let otherRoot = RootCandidateSource(root: other, options: RootScanOptions(depth: 2))
        let otherDepth = RootCandidateSource(root: tree.root, options: RootScanOptions(depth: 3))

        let otherRootMarker = try #require(try await otherRoot.trackedSnapshot().marker)
        let otherDepthMarker = try #require(try await otherDepth.trackedSnapshot().marker)

        #expect(await source.hasChanged(since: otherRootMarker))
        #expect(await source.hasChanged(since: otherDepthMarker))
    }

    @Test("キャンセルされたタスクから trackedSnapshot を呼ぶと CancellationError を投げる")
    func trackedSnapshotThrowsWhenCancelled() async throws {
        try tree.makeDirectories("a")
        let source = RootCandidateSource(root: tree.root, options: RootScanOptions())

        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await source.trackedSnapshot().snapshot }
        }
    }
}
