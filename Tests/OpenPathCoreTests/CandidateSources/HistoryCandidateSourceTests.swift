import Foundation
import Testing

import OpenPathCore

@Suite("HistoryCandidateSource")
struct HistoryCandidateSourceTests {
    private typealias F = HistoryFixtures

    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    private static func entries(_ paths: [String]) -> [HistoryEntry] {
        paths.map { HistoryEntry(path: $0, count: 1, lastUsed: F.now) }
    }

    @Test("kind は .history")
    func kindIsHistory() {
        let source = HistoryCandidateSource { [] }

        #expect(source.kind == .history)
    }

    @Test("履歴のパスを実在の種別で返し、存在しないパスは含めない")
    func classifiesExistingPaths() async throws {
        try tree.makeDirectories("dir")
        try tree.makeFiles("file.txt")
        let paths = [tree.path("dir"), tree.path("file.txt"), tree.path("missing")]
        let entries = Self.entries(paths)
        let source = HistoryCandidateSource { entries }

        let snapshot = try await source.snapshot()

        #expect(snapshot == CandidateSourceSnapshot(items: [.directory(tree.path("dir")), .file(tree.path("file.txt"))]))
    }

    @Test("シンボリックリンクはリンク先の種別で判定し、リンク切れは含めない")
    func classifiesSymlinksByTarget() async throws {
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("target"))
        try tree.makeSymbolicLink("dir-link", to: tree.outsidePath("target"))
        try tree.makeSymbolicLink("broken", to: tree.outsidePath("missing"))
        let entries = Self.entries([tree.path("dir-link"), tree.path("broken")])
        let source = HistoryCandidateSource { entries }

        let snapshot = try await source.snapshot()

        #expect(snapshot.items == [.directory(tree.path("dir-link"))])
    }

    @Test("パッケージ（.app）はファイルとして扱う")
    func treatsPackagesAsFiles() async throws {
        try tree.makeDirectories("Tool.app/Contents")
        let entries = Self.entries([tree.path("Tool.app")])
        let source = HistoryCandidateSource { entries }

        let snapshot = try await source.snapshot()

        #expect(snapshot.items == [.file(tree.path("Tool.app"))])
    }

    @Test("HistoryStore の履歴を MainActor 上で読み取って候補にする")
    @MainActor
    func readsEntriesFromHistoryStore() async throws {
        try tree.makeDirectories("recent")
        let persistence = HistoryPersistenceSpy(loadResult: .loaded(Self.entries([tree.path("recent")])))
        let store = HistoryStore(persistence: persistence, now: { F.now })
        let source = HistoryCandidateSource(store: store)

        let snapshot = try await source.snapshot()

        #expect(snapshot.items == [.directory(tree.path("recent"))])
    }

    @Test("キャンセルされたタスクから呼ぶと CancellationError を投げる")
    func throwsWhenCancelled() async throws {
        try tree.makeDirectories("dir")
        let entries = Self.entries([tree.path("dir")])
        let source = HistoryCandidateSource { entries }

        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await source.snapshot() }
        }
    }
}
