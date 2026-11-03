import Foundation
import Testing
import OpenPathCore

@Suite("アプリ別履歴", .timeLimit(.minutes(1)))
struct ApplicationHistoryTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let path = "/example/project"

    @Test("旧 JSON を情報を失わずに読み、新しいアプリ別実績を同じ配列へ保存する")
    func migratesLegacyJSON() throws {
        let legacy = """
        [{"path":"/example/project","count":7,"last_used":\(Self.now.timeIntervalSinceReferenceDate)}]
        """
        var list = HistoryList(entries: try JSONDecoder().decode([HistoryEntry].self, from: Data(legacy.utf8)))
        #expect(list.entries.first?.applications == [:])
        list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.editor")
        let data = try JSONEncoder().encode(list.entries)
        let reloaded = try JSONDecoder().decode([HistoryEntry].self, from: data)
        #expect(reloaded == list.entries)
        #expect(reloaded.first?.count == 8)
        #expect(reloaded.first?.applications["org.example.editor"]?.count == 1)
    }

    @Test("同じパスの全体実績と各アプリの実績を独立して増やす")
    func recordsGlobalAndAppCounts() {
        var list = HistoryList()
        list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.editor")
        list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.browser")
        list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.editor")
        #expect(list.entries.count == 1)
        #expect(list.entries[0].count == 3)
        #expect(list.entries[0].applications["org.example.editor"]?.count == 2)
        #expect(list.entries[0].applications["org.example.browser"]?.count == 1)
        #expect(list.entries[0].frecency(now: Self.now, applicationBundleID: "org.example.unknown") == list.entries[0].frecency(now: Self.now))
    }

    /// 同時刻でも直前に記録したアプリを保護し、無制限に辞書が増えないことを確かめる。
    @Test("アプリ実績を各パス8件に制限し、同時刻の新しいアプリも残す")
    func boundsAppRecords() throws {
        var list = HistoryList()
        for index in 0..<20 {
            list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.app\(index)")
        }
        let entry = try #require(list.entries.first)
        #expect(entry.count == 20)
        #expect(entry.applications.count == HistoryEntry.maxApplicationCount)
        #expect(entry.applications["org.example.app19"]?.count == 1)
        let oversized = HistoryEntry(path: Self.path, count: 20, lastUsed: Self.now, applications: Dictionary(uniqueKeysWithValues: (0..<20).map {
            ("org.example.app\($0)", ApplicationHistoryUsage(count: 1, lastUsed: Self.now.addingTimeInterval(Double($0))))
        }))
        #expect(oversized.applications.count == 8)
        #expect(oversized.applications["org.example.app0"] == nil)
    }

    @Test("不明・空・パネルサービスの ID は全体実績だけに残す")
    func excludesServiceIdentities() throws {
        var list = HistoryList()
        for app in [nil, "", "com.apple.appkit.xpc.openAndSavePanelService", "org.example.invalid name"] as [String?] {
            list.record(path: Self.path, now: Self.now, applicationBundleID: app)
        }
        let entry = try #require(list.entries.first)
        #expect(entry.count == 4)
        #expect(entry.applications.isEmpty)
    }

    @Test("重複パスのアプリ実績も回数を足し、最終使用は新しい方にする")
    func mergesDuplicateAppUsage() throws {
        let app = "org.example.editor"
        let first = HistoryEntry(path: Self.path, count: 2, lastUsed: Self.now, applications: [app: .init(count: 2, lastUsed: Self.now)])
        let second = HistoryEntry(path: Self.path, count: 3, lastUsed: Self.now.addingTimeInterval(1), applications: [app: .init(count: 3, lastUsed: Self.now.addingTimeInterval(1))])
        let entry = try #require(HistoryList(entries: [first, second]).entries.first)
        #expect(entry.count == 5)
        #expect(entry.applications[app]?.count == 5)
        #expect(entry.applications[app]?.lastUsed == second.lastUsed)
    }

    @Test("不存在の古いパスを掃除するとアプリ実績も一緒に消える")
    func prunesAppRecordsWithPath() {
        let old = Self.now.addingTimeInterval(-HistoryList.staleThreshold - 1)
        let entry = HistoryEntry(path: Self.path, count: 1, lastUsed: old, applications: ["org.example.editor": .init(count: 1, lastUsed: old)])
        let pruned = HistoryList(entries: [entry]).pruned(now: Self.now, fileExistence: StubFileExistenceChecker(existingPaths: []))
        #expect(pruned.entries.isEmpty)
    }

    @Test("アプリ実績があるパスも2000件の上限で削除する")
    func boundsPathsAndAppRecordsTogether() {
        let entries = (0..<HistoryList.maxEntryCount).map { index in
            HistoryEntry(path: "/example/path\(index)", count: 10, lastUsed: Self.now, applications: ["org.example.editor": .init(count: 10, lastUsed: Self.now)])
        }
        var list = HistoryList(entries: entries)
        list.record(path: Self.path, now: Self.now, applicationBundleID: "org.example.browser")
        #expect(list.entries.count == HistoryList.maxEntryCount)
        #expect(list.entry(for: Self.path)?.applications.count == 1)
    }

    @Test("再起動後もアプリ実績を読み、履歴クリアで全体・アプリの両方を保存先から消す")
    @MainActor
    func persistsAndClearsAppHistory() throws {
        let temporary = try HistoryTemporaryDirectory()
        let file = HistoryFile(directory: temporary.url)
        let store = HistoryStore(persistence: file, now: { Self.now })
        store.record(path: Self.path, applicationBundleID: "org.example.editor")
        store.flush()
        let reloaded = HistoryStore(persistence: file, now: { Self.now })
        #expect(reloaded.entries.first?.applications["org.example.editor"]?.count == 1)
        #expect(reloaded.clear())
        #expect(HistoryStore(persistence: file).entries.isEmpty)
    }
}
