import Foundation

/// query でも zoxide 自身が DB を保存するため、読み取り専用の元データから独立したコピーを作る。
/// DB のバイト列は解釈せず、公開 CLI の読み取りに任せる。新旧の db.txt / db.zo を扱う。
struct ZoxideDatabaseCopy: Sendable {
    /// zoxide が読み込める DB の最大サイズと同じ 32 MiB。巨大な任意ファイルの取り込みを避ける。
    static let maximumFileSize = 32 * 1024 * 1024
    let directory: URL

    /// 元の DB ファイルを独立した通常ファイルへコピーする。元が空なら nil。
    /// コピーに失敗したとき・DB が無いときは、作りかけの一時ディレクトリも削除する。
    static func make(environment: [String: String]) throws -> Self? {
        let source = try dataDirectory(environment: environment)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("openpath-zoxide-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keepCopy = false
        defer {
            if !keepCopy { try? FileManager.default.removeItem(at: temporary) }
        }
        var copiedCount = 0
        for name in ["db.txt", "db.zo"] {
            try Task.checkCancellation()
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: source.appendingPathComponent(name))
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                continue
            }
            defer { try? handle.close() }
            let destination = temporary.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ZoxideError.databaseUnavailable
            }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var size = 0
            // 小さな単位でコピーし、常駐メモリに DB 全体を載せない。
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                size += chunk.count
                guard size <= maximumFileSize else { throw ZoxideError.databaseTooLarge }
                try output.write(contentsOf: chunk)
            }
            copiedCount += 1
        }
        guard copiedCount > 0 else { return nil }
        keepCopy = true
        return Self(directory: temporary)
    }

    /// zoxide と同じく _ZO_DATA_DIR を優先し、未指定なら macOS のデータ保存先を使う。
    /// 相対パスや ~ の文字列は zoxide の仕様に合わせて拒否する。
    static func dataDirectory(environment: [String: String]) throws -> URL {
        let path: String
        if let override = environment["_ZO_DATA_DIR"] {
            path = override
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            path = home + "/Library/Application Support/zoxide"
        }
        guard path.hasPrefix("/"), !path.contains("\0") else { throw ZoxideError.invalidDataDirectory }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// 呼び出した CLI の終了後に使い捨てる。元のデータディレクトリには触れない。
    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Log.warning("zoxide の取得用一時ファイルを削除できませんでした")
        }
    }
}
