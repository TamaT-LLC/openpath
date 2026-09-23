import Foundation

import OpenPathCore

/// テストごとに作る一時ディレクトリ。実ユーザーの history.json に触れないために使う。
/// 破棄時に中身ごと削除する。
final class HistoryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "openpath-history-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// ファイル権限の検証用ヘルパ。
enum HistoryFilePermissions {
    static let ownerReadWrite = 0o600
    static let ownerAll = 0o700
    static let ownerReadExecute = 0o500
    static let worldReadable = 0o644
    private static let permissionBitsMask = 0o777

    /// 権限ビット（下位 9 ビット）。取得できない場合は nil。
    static func of(_ url: URL) throws -> Int? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? Int).map { $0 & permissionBitsMask }
    }

    static func set(_ permissions: Int, on url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path(percentEncoded: false))
    }
}

/// HistoryPersisting への呼び出しを記録する。
/// `backing` を渡すと実際の読み書きはそちらに委譲するため、実ファイルへのデバウンス保存も待ち合わせられる。
@MainActor
final class HistoryPersistenceSpy: HistoryPersisting {
    struct InjectedSaveError: Error {}

    private let stubbedLoadResult: HistoryLoadResult
    private let backing: (any HistoryPersisting)?
    private let waiter = ConditionWaiter()

    private(set) var loadCount = 0
    /// save が呼ばれた順の引数。失敗させた呼び出しも含む。
    private(set) var saveAttempts: [[HistoryEntry]] = []
    /// この回数だけ save を失敗させる。
    var remainingSaveFailures = 0

    init(loadResult: HistoryLoadResult = .notFound) {
        stubbedLoadResult = loadResult
        backing = nil
    }

    init(backing: any HistoryPersisting) {
        stubbedLoadResult = .notFound
        self.backing = backing
    }

    func load() -> HistoryLoadResult {
        loadCount += 1
        return backing?.load() ?? stubbedLoadResult
    }

    func save(_ entries: [HistoryEntry]) throws {
        saveAttempts.append(entries)
        defer { waiter.notify() }
        if remainingSaveFailures > 0 {
            remainingSaveFailures -= 1
            throw InjectedSaveError()
        }
        try backing?.save(entries)
    }

    func waitUntilSaveAttempted(times: Int = 1) async {
        await waiter.wait { self.saveAttempts.count >= times }
    }
}
