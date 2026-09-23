import Foundation
import Testing

import OpenPathCore

/// HistoryStore と HistoryFile を組み合わせ、一時ディレクトリ上の実ファイルで永続化を確かめる。
@Suite("HistoryStore: 実ファイルへの永続化", .timeLimit(.minutes(1)))
@MainActor
struct HistoryStorePersistenceTests {
    private typealias F = HistoryFixtures

    private static let brokenFileName = "history.json.broken-20260509T061320Z"

    private let temporaryDirectory: TemporaryDirectory
    private let clock = TestClock()

    init() throws {
        temporaryDirectory = try TemporaryDirectory()
    }

    private var historyFile: HistoryFile {
        HistoryFile(directory: temporaryDirectory.url, now: { F.now })
    }

    /// アプリの起動に相当する。同じディレクトリで作り直すと再起動後の状態を再現できる。
    private func launch(persistence: (any HistoryPersisting)? = nil) -> HistoryStore {
        HistoryStore(
            persistence: persistence ?? historyFile,
            clock: clock,
            now: { F.now },
            fileExistence: StubFileExistenceChecker()
        )
    }

    @Test("再起動後も履歴が保持される")
    func keepsHistoryAcrossRelaunch() {
        let store = launch()
        store.record(path: "/Users/example/repos/openpath")
        store.record(path: "/Users/example/Documents/資料")
        store.record(path: "/Users/example/repos/openpath")
        store.flush()

        let relaunched = launch()

        #expect(relaunched.loadResult == .loaded(store.entries))
        #expect(relaunched.entries == [
            HistoryEntry(path: "/Users/example/repos/openpath", count: 2, lastUsed: F.now),
            HistoryEntry(path: "/Users/example/Documents/資料", count: 1, lastUsed: F.now),
        ])
    }

    @Test("デバウンス後に実ファイルへ権限 0600 で保存される")
    func debouncedSaveWritesFile() async throws {
        let persistence = HistoryPersistenceSpy(backing: historyFile)
        let store = launch(persistence: persistence)

        store.record(path: "/a")
        clock.advance(by: HistoryStore.saveDebounceInterval)
        await persistence.waitUntilSaveAttempted()

        #expect(historyFile.load() == .loaded(store.entries))
        #expect(try FilePermissions.of(historyFile.fileURL) == FilePermissions.ownerReadWrite)
    }

    @Test("破損した history.json は退避され、空の履歴で起動して以後は新しいファイルに保存する")
    func recoversFromCorruptedFile() throws {
        let brokenContents = "[{\"path\": "
        try Data(brokenContents.utf8).write(to: historyFile.fileURL)

        let store = launch()

        let backupURL = temporaryDirectory.url.appending(path: Self.brokenFileName)
        #expect(store.loadResult == .corrupted(movedTo: backupURL))
        #expect(store.entries.isEmpty)
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == brokenContents)

        store.record(path: "/a")
        store.flush()

        #expect(launch().entries == [HistoryEntry(path: "/a", count: 1, lastUsed: F.now)])
        #expect(try FilePermissions.of(historyFile.fileURL) == FilePermissions.ownerReadWrite)
    }

    @Test("clear した後に再起動すると空の履歴になる")
    func clearPersistsAcrossRelaunch() {
        let store = launch()
        store.record(path: "/a")
        store.flush()

        store.clear()

        let relaunched = launch()
        #expect(relaunched.loadResult == .loaded([]))
        #expect(relaunched.entries.isEmpty)
    }
}
