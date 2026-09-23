import Foundation

import OpenPathCore

/// ConfigStore 系テストで共有する固定値と組み立て処理。
@MainActor
enum ConfigStoreFixtures {
    /// `~` の展開先。実ユーザーのホームに依存させない
    static let homeDirectory = "/Users/tester"
    static let ghqRoot = "/Users/tester/ghq"
    static let fileName = "config.toml"
    /// 設定ファイルを置くディレクトリ名。未作成の状態から始め、ディレクトリ作成の挙動も確かめる
    static let configDirectoryName = "openpath"

    /// ファイル監視の反映を待つ上限。通常は数百 ms で満たされるが、CI の遅い環境でも落ちないよう余裕を持たせる
    static let watchTimeout: Duration = .seconds(5)
    static let pollInterval: Duration = .milliseconds(20)
    /// 「反映されないこと」を確かめるときの待ち時間。fastTiming のデバウンスと再オープンより十分長くとる
    static let absenceWaitTimeout: Duration = .milliseconds(300)

    /// 監視の既定値より短くし、リトライを使い切る経路を速く確かめるためのタイミング
    static let fastTiming = ConfigFileWatchTiming(
        reopenDelay: .milliseconds(50),
        maxReopenAttempts: 2,
        debounceInterval: .milliseconds(20)
    )

    /// 再オープンの 1 回目（既定 200ms）より後に再作成し、リトライで追従できることを確かめるための待ち時間
    static let longerThanReopenDelay: Duration = .milliseconds(350)

    static func makeStore(
        directory: URL,
        ghqRoot: String? = ghqRoot,
        timing: ConfigFileWatchTiming = .default
    ) -> (store: ConfigStore, ghq: GhqRootProviderStub) {
        let ghq = GhqRootProviderStub(rootPath: ghqRoot)
        let store = ConfigStore(
            directory: directory,
            homeDirectory: homeDirectory,
            ghqRootProvider: ghq,
            watchTiming: timing
        )
        return (store, ghq)
    }

    /// 条件が満たされるまでポーリングで待つ。満たされたら true、上限まで満たされなければ false。
    /// イベントの到着時刻に依存させず、満たされた時点ですぐ次へ進めるようにする。
    static func waitUntil(
        timeout: Duration = watchTimeout,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: pollInterval)
        }
        return true
    }

    /// ストリームが終わるまでの値をすべて集める。
    static func collectAll(_ stream: AsyncStream<Config>) async -> [Config] {
        var received: [Config] = []
        for await config in stream {
            received.append(config)
        }
        return received
    }
}

/// テストごとの一時ディレクトリ。実ユーザーの ~/.config に触れないようにする。
final class ConfigStoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "openpath-config-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// 固定の ghq root を返し、問い合わせ回数を記録する GhqRootProviding。
actor GhqRootProviderStub: GhqRootProviding {
    private let rootPath: String?
    private(set) var callCount = 0

    init(rootPath: String?) {
        self.rootPath = rootPath
    }

    func root() async -> String? {
        callCount += 1
        return rootPath
    }
}

/// 設定ファイルの書き換え方。エディタの保存方式ごとの監視の追従を確かめる。
enum ConfigFileWriter {
    private static let temporaryExtension = "tmp"

    /// 同じ inode のまま中身を書き換える（上書き保存）。
    static func overwriteInPlace(_ url: URL, with contents: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(contents.utf8))
    }

    /// 同じディレクトリの別名に書いてから rename で置き換える（エディタのアトミック保存）。
    static func replaceAtomically(_ url: URL, with contents: String) throws {
        let temporaryURL = url.appendingPathExtension(temporaryExtension)
        try Data(contents.utf8).write(to: temporaryURL)
        guard rename(temporaryURL.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// 新しくファイルを作って書く。
    static func create(_ url: URL, with contents: String) throws {
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
    }

    static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
