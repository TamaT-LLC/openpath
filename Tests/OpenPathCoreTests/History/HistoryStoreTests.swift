import Foundation
import Testing

import OpenPathCore

@Suite("HistoryStore", .timeLimit(.minutes(1)))
@MainActor
struct HistoryStoreTests {
    private typealias F = HistoryFixtures

    private static let debounceInterval: Duration = .milliseconds(500)
    private static let oneMillisecond: Duration = .milliseconds(1)
    private static let staleDays = 91.0

    private let clock = TestClock()

    private func makeStore(
        persistence: HistoryPersistenceSpy,
        existingPaths: Set<String> = []
    ) -> HistoryStore {
        HistoryStore(
            persistence: persistence,
            clock: clock,
            now: { F.now },
            fileExistence: StubFileExistenceChecker(existingPaths: existingPaths)
        )
    }

    // MARK: - 読み込み

    @Test("起動時に 1 回だけ読み込み、読み込んだ履歴を entries として持つ")
    func loadsEntriesOnInit() {
        let loaded = [
            HistoryEntry(path: "/a", count: 2, lastUsed: F.ago(F.oneDay)),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.ago(F.oneHour)),
        ]
        let persistence = HistoryPersistenceSpy(loadResult: .loaded(loaded))

        let store = makeStore(persistence: persistence)

        #expect(persistence.loadCount == 1)
        #expect(store.loadResult == .loaded(loaded))
        #expect(store.entries == loaded)
    }

    @Test(
        "ファイルが無い・破損していた場合は空の履歴から始める",
        arguments: [
            HistoryLoadResult.notFound,
            .corrupted(movedTo: URL(filePath: "/tmp/history.json.broken-20260509T061320Z")),
            .corrupted(movedTo: nil),
        ]
    )
    func startsEmptyWithoutUsableFile(loadResult: HistoryLoadResult) {
        let store = makeStore(persistence: HistoryPersistenceSpy(loadResult: loadResult))

        #expect(store.loadResult == loadResult)
        #expect(store.entries.isEmpty)
    }

    // MARK: - 記録と取得

    @Test("record で count が増え lastUsed が現在時刻になり、新規パスは末尾に追加される")
    func recordUpdatesEntries() {
        let persistence = HistoryPersistenceSpy(loadResult: .loaded([
            HistoryEntry(path: "/a", count: 2, lastUsed: F.ago(F.oneDay)),
        ]))
        let store = makeStore(persistence: persistence)

        store.record(path: "/a")
        store.record(path: "/b")

        #expect(store.entries == [
            HistoryEntry(path: "/a", count: 3, lastUsed: F.now),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.now),
        ])
    }

    @Test("HistoryRecording として AppCoordinator から記録できる")
    func recordsThroughHistoryRecording() {
        let store = makeStore(persistence: HistoryPersistenceSpy())
        let recording: any HistoryRecording = store

        recording.record(path: "/a")

        #expect(store.entries == [HistoryEntry(path: "/a", count: 1, lastUsed: F.now)])
    }

    @Test("sortedByFrecency は frecency 降順で返す")
    func sortedByFrecencyDescending() {
        let persistence = HistoryPersistenceSpy(loadResult: .loaded([
            HistoryEntry(path: "/low", count: 1, lastUsed: F.ago(10 * F.oneDay)), // 0.25
            HistoryEntry(path: "/high", count: 3, lastUsed: F.ago(2 * F.oneHour)), // 6.0
            HistoryEntry(path: "/mid", count: 1, lastUsed: F.ago(30 * F.oneMinute)), // 4.0
        ]))
        let store = makeStore(persistence: persistence)

        #expect(store.sortedByFrecency(now: F.now).map(\.path) == ["/high", "/mid", "/low"])
    }

    // MARK: - デバウンス保存

    @Test("デバウンス間隔は 500ms")
    func debounceIntervalIs500Milliseconds() {
        #expect(HistoryStore.saveDebounceInterval == Self.debounceInterval)
    }

    @Test("record 直後は保存せず、500ms 経過した時点で保存する")
    func savesAfterDebounceInterval() async {
        let persistence = HistoryPersistenceSpy()
        let store = makeStore(persistence: persistence)

        store.record(path: "/a")
        clock.advance(by: Self.debounceInterval - Self.oneMillisecond)
        await MainActorDrain.run()
        #expect(persistence.saveAttempts.isEmpty)

        clock.advance(by: Self.oneMillisecond)
        await persistence.waitUntilSaveAttempted()

        #expect(persistence.saveAttempts == [store.entries])
    }

    @Test("500ms 以内の連続した record は、最後の record から 500ms 後にまとめて 1 回だけ保存する")
    func coalescesConsecutiveRecords() async {
        let persistence = HistoryPersistenceSpy()
        let store = makeStore(persistence: persistence)
        let interval: Duration = .milliseconds(300)

        store.record(path: "/a")
        clock.advance(by: interval)
        store.record(path: "/b")
        clock.advance(by: interval)
        store.record(path: "/a")
        clock.advance(by: interval)
        await MainActorDrain.run()
        #expect(persistence.saveAttempts.isEmpty)

        clock.advance(by: Self.debounceInterval - interval)
        await persistence.waitUntilSaveAttempted()
        clock.advance(by: Self.debounceInterval)
        await MainActorDrain.run()

        #expect(persistence.saveAttempts == [[
            HistoryEntry(path: "/a", count: 2, lastUsed: F.now),
            HistoryEntry(path: "/b", count: 1, lastUsed: F.now),
        ]])
    }

    // MARK: - flush

    @Test("flush は保留中の変更を即座に保存し、デバウンスによる保存は行わない")
    func flushSavesImmediatelyAndCancelsPendingSave() async {
        let persistence = HistoryPersistenceSpy()
        let store = makeStore(persistence: persistence)
        store.record(path: "/a")

        store.flush()

        #expect(persistence.saveAttempts == [[HistoryEntry(path: "/a", count: 1, lastUsed: F.now)]])
        clock.advance(by: Self.debounceInterval)
        await MainActorDrain.run()
        #expect(persistence.saveAttempts.count == 1)
    }

    @Test("未保存の変更がなければ flush しても保存しない")
    func flushWithoutChangesDoesNotSave() {
        let persistence = HistoryPersistenceSpy(loadResult: .loaded([
            HistoryEntry(path: "/a", count: 1, lastUsed: F.now),
        ]))
        let store = makeStore(persistence: persistence)

        store.flush()
        store.record(path: "/b")
        store.flush()
        store.flush()

        #expect(persistence.saveAttempts.count == 1)
    }

    @Test("保存に失敗しても変更は保持し、次の flush で保存し直す")
    func retriesAfterSaveFailure() {
        let persistence = HistoryPersistenceSpy()
        persistence.remainingSaveFailures = 1
        let store = makeStore(persistence: persistence)
        store.record(path: "/a")

        store.flush()
        store.flush()

        let expected = [HistoryEntry(path: "/a", count: 1, lastUsed: F.now)]
        #expect(store.entries == expected)
        #expect(persistence.saveAttempts == [expected, expected])
    }

    // MARK: - clear

    @Test("clear は未保存の変更が無くても、履歴を空にして即座に保存する")
    func clearEmptiesAndSavesImmediately() {
        let persistence = HistoryPersistenceSpy(loadResult: .loaded([
            HistoryEntry(path: "/a", count: 5, lastUsed: F.ago(F.oneDay)),
        ]))
        let store = makeStore(persistence: persistence)

        store.clear()

        #expect(store.entries.isEmpty)
        #expect(persistence.saveAttempts == [[]])
    }

    @Test("clear の前に保留していたデバウンス保存は行わない")
    func clearCancelsPendingSave() async {
        let persistence = HistoryPersistenceSpy()
        let store = makeStore(persistence: persistence)
        store.record(path: "/a")

        store.clear()
        clock.advance(by: Self.debounceInterval)
        await MainActorDrain.run()

        #expect(persistence.saveAttempts == [[]])
    }

    // MARK: - 掃除

    @Test("FR-HISTORY-03: 保存時に 90 日以上未使用かつ存在しないエントリを削除し、メモリ上からも除く")
    func prunesStaleMissingEntriesOnSave() {
        let staleExisting = HistoryEntry(path: "/stale-existing", count: 1, lastUsed: F.ago(Self.staleDays * F.oneDay))
        let recentMissing = HistoryEntry(path: "/recent-missing", count: 1, lastUsed: F.ago(F.oneDay))
        let persistence = HistoryPersistenceSpy(loadResult: .loaded([
            HistoryEntry(path: "/stale-missing", count: 9, lastUsed: F.ago(Self.staleDays * F.oneDay)),
            staleExisting,
            recentMissing,
        ]))
        let store = makeStore(persistence: persistence, existingPaths: ["/stale-existing", "/new"])
        store.record(path: "/new")

        store.flush()

        let expected = [staleExisting, recentMissing, HistoryEntry(path: "/new", count: 1, lastUsed: F.now)]
        #expect(persistence.saveAttempts == [expected])
        #expect(store.entries == expected)
    }
}
