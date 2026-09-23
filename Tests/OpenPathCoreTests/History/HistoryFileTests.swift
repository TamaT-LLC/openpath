import Foundation
import Testing

import OpenPathCore

@Suite("HistoryFile")
struct HistoryFileTests {
    private typealias F = HistoryFixtures

    private static let appDirectoryName = "openpath"
    private static let fileName = "history.json"
    /// F.now を UTC の ISO 8601（秒精度）で表した文字列。
    private static let nowISO8601 = "2026-05-09T06:13:20Z"
    /// 退避ファイル名の末尾（F.now を ISO 8601 基本形式で表したもの）。
    private static let brokenFileName = "history.json.broken-20260509T061320Z"
    private static let subSecond: TimeInterval = 0.9

    private let temporaryDirectory: HistoryTemporaryDirectory
    /// 保存先。未作成の状態から始め、ディレクトリ作成の挙動も確かめる。
    private let directory: URL
    private let file: HistoryFile

    init() throws {
        temporaryDirectory = try HistoryTemporaryDirectory()
        directory = temporaryDirectory.url.appending(path: Self.appDirectoryName, directoryHint: .isDirectory)
        file = HistoryFile(directory: directory, now: { F.now })
    }

    private var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    private func writeRaw(_ contents: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: - 保存先

    @Test("FR-HISTORY-04: 既定の保存先は ~/Library/Application Support/openpath")
    func defaultDirectoryIsApplicationSupport() {
        let components = HistoryFile.defaultDirectory.pathComponents

        #expect(Array(components.suffix(3)) == ["Library", "Application Support", Self.appDirectoryName])
    }

    @Test("ファイル名は history.json")
    func fileURLIsHistoryJSONInDirectory() {
        #expect(file.directory == directory)
        #expect(file.fileURL == fileURL)
    }

    // MARK: - 読み込み

    @Test("ファイルが無ければ notFound を返し、ディレクトリも作らない")
    func loadReturnsNotFoundWhenMissing() {
        #expect(file.load() == .notFound)
        #expect(!Self.exists(directory))
    }

    @Test("空配列の JSON は空の履歴として読み込める")
    func loadsEmptyArray() throws {
        try writeRaw("[]")

        #expect(file.load() == .loaded([]))
    }

    @Test("保存した履歴を読み込むと一致する")
    func roundTrips() throws {
        let entries = [
            HistoryEntry(path: "/Users/example/repos/openpath", count: 3, lastUsed: F.now),
            HistoryEntry(path: "/Users/example/Documents/資料", count: 12, lastUsed: F.ago(100 * F.oneDay)),
        ]

        try file.save(entries)

        #expect(file.load() == .loaded(entries))
    }

    // MARK: - JSON 形式

    @Test("JSON は HistoryEntry の配列で、last_used は UTC の ISO 8601（秒精度）")
    func encodesArrayWithISO8601Dates() throws {
        let path = "/Users/example/repos/openpath"
        try file.save([HistoryEntry(path: path, count: 3, lastUsed: F.now)])

        let data = try Data(contentsOf: fileURL)
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let object = try #require(array.first)
        #expect(array.count == 1)
        #expect(object["path"] as? String == path)
        #expect(object["count"] as? Int == 3)
        #expect(object["last_used"] as? String == Self.nowISO8601)
        // 手で読めるよう `/` をエスケープしない
        #expect(String(decoding: data, as: UTF8.self).contains(path))
    }

    @Test("秒未満は切り捨てて保存する")
    func truncatesSubSecondPrecision() throws {
        try file.save([HistoryEntry(path: "/a", count: 1, lastUsed: F.now.addingTimeInterval(Self.subSecond))])

        #expect(file.load() == .loaded([HistoryEntry(path: "/a", count: 1, lastUsed: F.now)]))
    }

    // MARK: - 権限

    @Test("保存したファイルの権限は 0600")
    func savedFileIsOwnerReadWriteOnly() throws {
        try file.save([HistoryEntry(path: "/a", count: 1, lastUsed: F.now)])

        #expect(try HistoryFilePermissions.of(fileURL) == HistoryFilePermissions.ownerReadWrite)
    }

    @Test("権限が変わっていても、上書き保存で 0600 に戻る")
    func overwriteRestoresOwnerReadWrite() throws {
        try file.save([HistoryEntry(path: "/a", count: 1, lastUsed: F.now)])
        try HistoryFilePermissions.set(HistoryFilePermissions.worldReadable, on: fileURL)

        try file.save([HistoryEntry(path: "/a", count: 2, lastUsed: F.now)])

        #expect(try HistoryFilePermissions.of(fileURL) == HistoryFilePermissions.ownerReadWrite)
    }

    @Test("保存先ディレクトリが無ければ権限 0700 で作成する")
    func createsDirectoryWithOwnerOnlyPermissions() throws {
        try file.save([])

        #expect(try HistoryFilePermissions.of(directory) == HistoryFilePermissions.ownerAll)
    }

    @Test("保存先ディレクトリを作れなければ保存はエラーになる")
    func saveThrowsWhenDirectoryCannotBeCreated() throws {
        // 同名の通常ファイルを置き、ディレクトリを作れなくする
        try Data().write(to: temporaryDirectory.url.appending(path: Self.appDirectoryName, directoryHint: .notDirectory))

        #expect(throws: (any Error).self) {
            try file.save([])
        }
    }

    // MARK: - 破損時の退避

    @Test("壊れた history.json は history.json.broken-<timestamp> に退避して corrupted を返す")
    func movesBrokenFileAside() throws {
        let brokenContents = "{not json"
        try writeRaw(brokenContents)

        let result = file.load()

        let backupURL = directory.appending(path: Self.brokenFileName)
        #expect(result == .corrupted(movedTo: backupURL))
        #expect(!Self.exists(fileURL))
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == brokenContents)
    }

    @Test(
        "HistoryEntry の配列として読めない内容は破損として扱う",
        arguments: [
            "",
            "{}",
            #"{"path": "/a", "count": 1, "last_used": "2026-05-09T06:13:20Z"}"#,
            #"[{"path": "/a", "count": 1}]"#,
            // 日付が ISO 8601 でない（JSONDecoder 既定の数値形式）
            #"[{"path": "/a", "count": 1, "last_used": 800000000}]"#,
        ]
    )
    func treatsUndecodableContentsAsCorrupted(contents: String) throws {
        try writeRaw(contents)

        #expect(file.load() == .corrupted(movedTo: directory.appending(path: Self.brokenFileName)))
    }

    @Test("退避後に保存すると新しい history.json を作り、退避ファイルは残す")
    func saveAfterRecoveryKeepsBackup() throws {
        try writeRaw("{not json")
        _ = file.load()
        let entries = [HistoryEntry(path: "/a", count: 1, lastUsed: F.now)]

        try file.save(entries)

        #expect(file.load() == .loaded(entries))
        #expect(Self.exists(directory.appending(path: Self.brokenFileName)))
    }

    @Test("退避に失敗した場合は movedTo が nil の corrupted を返す")
    func reportsNilBackupWhenMoveFails() throws {
        try writeRaw("{not json")
        // 読み取りはできるがリネームできないよう、ディレクトリを書き込み不可にする
        try HistoryFilePermissions.set(HistoryFilePermissions.ownerReadExecute, on: directory)
        defer { try? HistoryFilePermissions.set(HistoryFilePermissions.ownerAll, on: directory) }

        #expect(file.load() == .corrupted(movedTo: nil))
        #expect(Self.exists(fileURL))
    }
}
