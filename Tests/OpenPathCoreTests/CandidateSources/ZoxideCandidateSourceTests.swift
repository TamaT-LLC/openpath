import Foundation
import Testing

@testable import OpenPathCore

/// 一時的な入力 DB と偽の CLI を使い、実ユーザーの zoxide データを変更せず検証する。
@Suite("Zoxide 連携", .timeLimit(.minutes(1)))
struct ZoxideCandidateSourceTests {
    private let tree: FileTreeFixture
    private static let searchPath = "/opt/homebrew/bin:/usr/bin:/bin"
    private static let timeout: Duration = .seconds(3)

    init() throws { tree = try FileTreeFixture() }

    private var environment: [String: String] {
        ["HOME": "/Users/example", "PATH": "/usr/bin:/bin", "_ZO_DATA_DIR": tree.root, "LANG": "ja_JP.UTF-8"]
    }

    private func makeDatabase(_ text: String = "original database") throws {
        try Data(text.utf8).write(to: URL(filePath: tree.path("db.zo")))
    }

    private func lister(
        runner: any CommandRunning, enabled: Bool = true,
        pathProvider: any SearchPathProviding = SearchPathProviderSpy(path: searchPath),
        installedDirectory: String? = "/opt/homebrew/bin"
    ) -> ZoxideDirectoryLister {
        ZoxideDirectoryLister(
            isEnabled: enabled, runner: runner, searchPathProvider: pathProvider,
            executableLocator: StubExecutableLocator(installedDirectory: installedDirectory),
            baseEnvironment: environment, commandTimeout: Self.timeout
        )
    }

    @Test("公開 CLI にコピーだけを渡し、コマンドが保存しても元の DB は全バイト一致で保つ")
    func queriesPrivateDatabaseCopy() async throws {
        try makeDatabase()
        let original = try Data(contentsOf: URL(filePath: tree.path("db.zo")))
        let originalPath = tree.root
        let runner = CommandRunnerMock { invocation in
            let environment = try #require(invocation.environment)
            let copiedPath = try #require(environment["_ZO_DATA_DIR"])
            #expect(copiedPath != originalPath)
            #expect(invocation.executable == "/opt/homebrew/bin/zoxide")
            #expect(invocation.arguments == ["query", "--list", "--all"])
            #expect(invocation.timeout == Self.timeout)
            #expect(environment["PATH"] == Self.searchPath)
            #expect(environment["HOME"] == "/Users/example")
            let copyFile = URL(filePath: copiedPath).appendingPathComponent("db.zo")
            #expect(try Data(contentsOf: copyFile) == original)
            let permissions = try FileManager.default.attributesOfItem(atPath: copiedPath)[.posixPermissions] as? Int
            #expect(permissions == 0o700)
            try Data("query rewrote its database".utf8).write(to: copyFile)
            return .succeeded(output: "/example/資料 with spaces/\n/example/資料 with spaces\n/example/other\nrelative\n")
        }

        let result = await lister(runner: runner).listDirectories()

        #expect(result == ZoxideListing(directoryPaths: ["/example/資料 with spaces", "/example/other"]))
        #expect(try Data(contentsOf: URL(filePath: tree.path("db.zo"))) == original)
        let invocation = try #require(await runner.invocations.first)
        let copiedPath = try #require(invocation.environment?["_ZO_DATA_DIR"])
        #expect(!FileManager.default.fileExists(atPath: copiedPath))
    }

    @Test("disabled は PATH・DB・CLI を読み取らない")
    func disabledDoesNoWork() async {
        let runner = CommandRunnerMock { _ in Issue.record("CLI should not run"); return .succeeded(output: "") }
        let path = SearchPathProviderSpy(path: Self.searchPath)
        let result = await lister(runner: runner, enabled: false, pathProvider: path).listDirectories()
        #expect(result == ZoxideListing(directoryPaths: []))
        #expect(await path.callCount == 0)
        #expect(await runner.invocations.isEmpty)
    }

    @Test("未インストールでも空の候補と警告を返す")
    func missingExecutableIsNonfatal() async throws {
        let runner = CommandRunnerMock { _ in Issue.record("CLI should not run"); return .succeeded(output: "") }
        let source = ZoxideCandidateSource(lister: lister(runner: runner, installedDirectory: nil))
        let snapshot = try await source.snapshot()
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.zoxideFailed(.notInstalled(searchPath: Self.searchPath))])
        #expect(await runner.invocations.isEmpty)
    }

    @Test("DB がない環境では空の一覧を返し、元のデータディレクトリも作らない")
    func missingDatabaseIsEmpty() async {
        let runner = CommandRunnerMock { _ in Issue.record("CLI should not run"); return .succeeded(output: "") }
        let result = await lister(runner: runner).listDirectories()
        #expect(result == ZoxideListing(directoryPaths: []))
        #expect(await runner.invocations.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tree.path("db.zo")))
        #expect(!FileManager.default.fileExists(atPath: tree.path("db.txt")))
    }

    @Test("失敗・タイムアウト・起動失敗では元を変更せず一時コピーを削除する", arguments: ["exit", "timeout", "launch"])
    func failuresCleanUp(mode: String) async throws {
        try makeDatabase()
        let runner = CommandRunnerMock { invocation in
            switch mode {
            case "timeout": throw CommandRunnerError.timedOut(executable: invocation.executable, timeout: invocation.timeout)
            case "launch": throw CommandRunnerError.launchFailed(executable: invocation.executable, reason: "example")
            default: return CommandResult(exitCode: 2, standardOutput: "/partial", standardError: "/private/path")
            }
        }
        let result = await lister(runner: runner).listDirectories()
        let expected: ZoxideError = mode == "timeout" ? .timedOut : (mode == "launch" ? .launchFailed : .nonZeroExit(2))
        #expect(result == ZoxideListing(directoryPaths: [], failure: expected))
        let invocation = try #require(await runner.invocations.first)
        let copiedPath = try #require(invocation.environment?["_ZO_DATA_DIR"])
        #expect(!FileManager.default.fileExists(atPath: copiedPath))
        #expect(try String(contentsOfFile: tree.path("db.zo"), encoding: .utf8) == "original database")
    }

    @Test("CLI のキャンセルは候補を空で上書きせず CancellationError を返す")
    func cancellationIsPropagated() async throws {
        try makeDatabase()
        let runner = CommandRunnerMock { _ in throw CancellationError() }
        let source = ZoxideCandidateSource(lister: lister(runner: runner))
        await #expect(throws: CancellationError.self) { try await source.snapshot() }
        let invocation = try #require(await runner.invocations.first)
        let copiedPath = try #require(invocation.environment?["_ZO_DATA_DIR"])
        #expect(!FileManager.default.fileExists(atPath: copiedPath))
    }

    @Test("キャンセル済みなら PATH や CLI を実行しない")
    func alreadyCancelledDoesNoWork() async {
        let runner = CommandRunnerMock { _ in Issue.record("CLI should not run"); return .succeeded(output: "") }
        let source = ZoxideCandidateSource(lister: lister(runner: runner))
        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await source.snapshot() }
        }
        #expect(await runner.invocations.isEmpty)
    }

    @Test("実在するディレクトリだけを返し、ファイル・パッケージ・切れたリンクは除外する")
    func checksDirectoryKinds() async throws {
        try makeDatabase()
        try tree.makeDirectories("資料 with spaces", "Sample.app/Contents")
        try tree.makeFiles("file.txt")
        try tree.makeSymbolicLink("linked", to: tree.path("資料 with spaces"))
        let output = ["資料 with spaces", "資料 with spaces/", "Sample.app", "file.txt", "linked", "missing"].map(tree.path).joined(separator: "\n")
        let runner = CommandRunnerMock { _ in .succeeded(output: output) }
        let snapshot = try await ZoxideCandidateSource(lister: lister(runner: runner)).snapshot()
        #expect(snapshot.warnings.isEmpty)
        #expect(snapshot.itemSet == [.directory(tree.path("資料 with spaces")), .directory(tree.path("linked"))])
        #expect(snapshot.items.count == 2)
    }

    @Test("他ソースと同一パスを統合し、openpath の履歴順位を維持する")
    @MainActor
    func mergesWithIndexAndKeepsHistoryRanking() async throws {
        try makeDatabase()
        try tree.makeDirectories("a", "b")
        let a = tree.path("a")
        let b = tree.path("b")
        let runner = CommandRunnerMock { _ in .succeeded(output: a + "\n" + b + "\n") }
        let source = ZoxideCandidateSource(lister: lister(runner: runner))
        let index = CandidateIndex(history: { [HistoryEntry(path: b, count: 10, lastUsed: Date())] })
        await index.replace(source: .ghq, with: [.directory(a)])
        await index.replace(source: .root(tree.root), with: [.directory(a)])
        await index.replace(source: source.kind, with: try await source.snapshot().items)
        let result = try await index.query("", directoriesOnly: true, limit: 50)
        #expect(result.map(\.candidate.path) == [b, a])
        #expect(result.map(\.candidate.source) == [.zoxide, .ghq])
        #expect(index.count == 2)
    }

    @Test("テキスト DB もコピーし、シンボリックリンクの保存先を元へ持ち込まない")
    func textDatabaseIsIndependent() throws {
        try Data("text database".utf8).write(to: URL(filePath: tree.outsidePath("db.txt")))
        try tree.makeSymbolicLink("db.txt", to: tree.outsidePath("db.txt"))
        let created = try ZoxideDatabaseCopy.make(environment: environment)
        let copy = try #require(created)
        defer { copy.remove() }
        let copiedFile = copy.directory.appendingPathComponent("db.txt")
        #expect(try copiedFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        try Data("changed".utf8).write(to: copiedFile)
        #expect(try String(contentsOfFile: tree.outsidePath("db.txt"), encoding: .utf8) == "text database")
    }

    @Test("zoxide と同じ保存先を使い、相対パスの override は拒否する")
    func dataDirectoryResolution() throws {
        #expect(try ZoxideDatabaseCopy.dataDirectory(environment: ["HOME": "/Users/example"]).path == "/Users/example/Library/Application Support/zoxide")
        #expect(try ZoxideDatabaseCopy.dataDirectory(environment: ["_ZO_DATA_DIR": "/custom/path"]).path == "/custom/path")
        #expect(throws: ZoxideError.invalidDataDirectory) { try ZoxideDatabaseCopy.dataDirectory(environment: ["_ZO_DATA_DIR": "relative"]) }
    }

    @Test("巨大な入力 DB を上限で拒否し、取得失敗として継続する")
    func rejectsOversizedDatabase() async throws {
        try makeDatabase()
        let handle = try FileHandle(forWritingTo: URL(filePath: tree.path("db.zo")))
        try handle.truncate(atOffset: UInt64(ZoxideDatabaseCopy.maximumFileSize + 1))
        try handle.close()
        let runner = CommandRunnerMock { _ in Issue.record("CLI should not run"); return .succeeded(output: "") }
        let result = await lister(runner: runner).listDirectories()
        #expect(result == ZoxideListing(directoryPaths: [], failure: .databaseTooLarge))
        #expect(await runner.invocations.isEmpty)
    }

    @Test("パスの末尾空白を保持し、不正な行と NUL を含む行は候補にしない")
    func preservesSpacesInOutput() {
        #expect(ZoxideDirectoryLister.paths(from: "/folder with spaces \n/folder with spaces /\nrelative\n\n/bad\0name\n/other\r\n") == ["/folder with spaces ", "/other"])
    }
}
