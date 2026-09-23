import Foundation
import Testing

import OpenPathCore

@Suite("HistoryEntry")
struct HistoryEntryTests {
    private typealias F = HistoryFixtures

    private static let samplePath = "/Users/example/repos/openpath"

    @Test("frecency は count と最終使用からの経過時間で決まる")
    func frecencyUsesCountAndLastUsed() {
        let entry = HistoryEntry(path: Self.samplePath, count: 4, lastUsed: F.ago(10 * F.oneDay))

        #expect(entry.frecency(now: F.now) == 1.0)
    }

    @Test("JSON のキーは path / count / last_used（ARCH-001 §8）")
    func encodesWithSnakeCaseLastUsedKey() throws {
        let entry = HistoryEntry(path: Self.samplePath, count: 3, lastUsed: F.now)

        let data = try JSONEncoder().encode(entry)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["path", "count", "last_used"])
        #expect(object["path"] as? String == Self.samplePath)
        #expect(object["count"] as? Int == 3)
    }

    @Test("last_used キーの JSON からデコードできる")
    func decodesFromSnakeCaseJSON() throws {
        let json = """
        {"path": "/tmp/project", "count": 7, "last_used": \(F.now.timeIntervalSinceReferenceDate)}
        """

        let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(json.utf8))

        #expect(entry == HistoryEntry(path: "/tmp/project", count: 7, lastUsed: F.now))
    }

    @Test("エンコードしてデコードすると元の値に戻る")
    func roundTripsThroughJSON() throws {
        let entries = [
            HistoryEntry(path: Self.samplePath, count: 1, lastUsed: F.now),
            HistoryEntry(path: "/Users/example/Documents/資料", count: 12, lastUsed: F.ago(F.oneWeek)),
        ]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)

        #expect(decoded == entries)
    }
}
