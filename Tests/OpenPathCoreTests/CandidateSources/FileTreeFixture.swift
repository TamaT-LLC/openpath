import Foundation

import OpenPathCore

/// テストごとに一時ディレクトリへ走査対象の木構造を作る。破棄時に中身ごと削除する。
///
/// `root` を走査対象のルートにし、シンボリックリンクの行き先などルートの外に置くものは `outside` 配下に作る。
/// どちらも `FileManager.temporaryDirectory` 由来の `/var/...` 表記で、実体は `/private/var/...` にある。
final class FileTreeFixture {
    private static let pathSeparator = "/"
    /// 権限を落としたディレクトリを、削除できるよう戻すときの権限
    static let ownerAllPermissions = 0o755
    static let noPermissions = 0o000

    let base: URL
    let root: String
    let outside: String

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appending(path: "openpath-candidate-source-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        root = Self.path(of: base.appending(path: "root"))
        outside = Self.path(of: base.appending(path: "outside"))
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    /// ルートからの相対パスを絶対パスにする。空文字ならルート自身。
    func path(_ relativePath: String) -> String {
        relativePath.isEmpty ? root : root + Self.pathSeparator + relativePath
    }

    /// ルートの外（`outside` 配下）の相対パスを絶対パスにする。
    func outsidePath(_ relativePath: String) -> String {
        outside + Self.pathSeparator + relativePath
    }

    /// ルートからの相対パスでディレクトリを作る。途中のディレクトリも作る。
    func makeDirectories(_ relativePaths: String...) throws {
        for relativePath in relativePaths {
            try Self.makeDirectory(atPath: path(relativePath))
        }
    }

    /// ルートからの相対パスで空のファイルを作る。親ディレクトリも作る。
    func makeFiles(_ relativePaths: String...) throws {
        for relativePath in relativePaths {
            try Self.makeFile(atPath: path(relativePath))
        }
    }

    /// ルートからの相対パスに、`destination`（絶対パス）を指すシンボリックリンクを作る。
    func makeSymbolicLink(_ relativePath: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path(relativePath), withDestinationPath: destination)
    }

    static func makeDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func makeFile(atPath path: String) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    static func makeSymbolicLink(atPath path: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
    }

    /// 権限を変える。権限を落とした場合は削除できなくなるため、テストの最後に `ownerAllPermissions` へ戻すこと。
    static func setPermissions(_ permissions: Int, atPath path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }

    /// URL の directoryHint によって末尾に付く `/` を除いたパス。
    private static func path(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.hasSuffix(pathSeparator) ? String(path.dropLast()) : path
    }
}

extension SourceItem {
    static func directory(_ path: String) -> SourceItem {
        SourceItem(path: path, isDirectory: true)
    }

    static func file(_ path: String) -> SourceItem {
        SourceItem(path: path, isDirectory: false)
    }
}

extension CandidateSourceSnapshot {
    /// 走査順はファイルシステムに依存するため、集合で比較する。重複の検出には `items.count` を併せて見ること。
    var itemSet: Set<SourceItem> {
        Set(items)
    }

    var pathSet: Set<String> {
        Set(items.map(\.path))
    }
}

/// 指定回数目の問い合わせからキャンセル済みと答える。走査の途中でキャンセルされた状況を決定的に再現する。
final class CancelAfterChecks: @unchecked Sendable {
    private let lock = NSLock()
    private let threshold: Int
    private var checkCount = 0

    init(threshold: Int) {
        self.threshold = threshold
    }

    func isCancelled() -> Bool {
        lock.withLock {
            checkCount += 1
            return checkCount >= threshold
        }
    }
}

/// キャンセルされるまで待ってから `body` を実行するタスクを作り、即座にキャンセルする。
/// 待機はキャンセルで即座に終わるため、`body` は必ずキャンセル済みの状態で実行される。
enum CancelledTaskRunner {
    private static let waitUntilCancelled: Duration = .seconds(60)

    static func run<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task {
            try? await Task.sleep(for: waitUntilCancelled)
            return try await body()
        }
        task.cancel()
        return try await task.value
    }
}
