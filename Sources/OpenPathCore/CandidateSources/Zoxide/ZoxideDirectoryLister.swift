import Foundation

/// zoxide の公開 CLI からディレクトリ一覧を取得する。GUI 起動用の PATH とコマンド実行は ghq と共通。
/// 元の DB は変更せず、query の保存・移行・掃除は一時コピーに限定する。
public struct ZoxideDirectoryLister: Sendable {
    public static let defaultCommandTimeout: Duration = .seconds(10)
    private let isEnabled: Bool
    private let runner: any CommandRunning
    private let searchPathProvider: any SearchPathProviding
    private let executableLocator: any ExecutableLocating
    private let baseEnvironment: [String: String]
    private let commandTimeout: Duration

    /// 無効時は PATH の取得もファイル読み取りも行わない。環境と実行器はテストで置き換えられる。
    public init(
        isEnabled: Bool,
        runner: any CommandRunning = ProcessCommandRunner(),
        searchPathProvider: any SearchPathProviding = LoginShellPathResolver(),
        executableLocator: any ExecutableLocating = SearchPathExecutableLocator(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        commandTimeout: Duration = defaultCommandTimeout
    ) {
        self.isEnabled = isEnabled
        self.runner = runner
        self.searchPathProvider = searchPathProvider
        self.executableLocator = executableLocator
        self.baseEnvironment = baseEnvironment
        self.commandTimeout = commandTimeout
    }

    /// query --list --all のパスだけを返す。失敗は空の一覧と理由で返し、他のソースを妨げない。
    public func listDirectories() async -> ZoxideListing {
        guard isEnabled else { return ZoxideListing(directoryPaths: []) }
        do {
            try Task.checkCancellation()
            let searchPath = await searchPathProvider.searchPath()
            try Task.checkCancellation()
            guard let executable = executableLocator.locateExecutable(named: "zoxide", inSearchPath: searchPath) else {
                throw ZoxideError.notInstalled(searchPath: searchPath)
            }
            let copy: ZoxideDatabaseCopy?
            do {
                copy = try ZoxideDatabaseCopy.make(environment: baseEnvironment)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ZoxideError {
                throw error
            } catch {
                throw ZoxideError.databaseUnavailable
            }
            guard let copy else { return ZoxideListing(directoryPaths: []) }
            defer { copy.remove() }
            var environment = baseEnvironment
            environment["PATH"] = searchPath
            environment["_ZO_DATA_DIR"] = copy.directory.path
            let result = try await runner.run(
                executable: executable, arguments: ["query", "--list", "--all"],
                environment: environment, timeout: commandTimeout
            )
            try Task.checkCancellation()
            guard result.exitCode == 0 else { throw ZoxideError.nonZeroExit(result.exitCode) }
            return ZoxideListing(directoryPaths: Self.paths(from: result.standardOutput))
        } catch {
            let failure = Self.failure(from: error)
            log(failure)
            return ZoxideListing(directoryPaths: [], failure: failure)
        }
    }

    /// 一行一パスを解釈し、字句的に正規化して先勝ちで統合する。空白はパス名の一部として保持する。
    static func paths(from output: String) -> [String] {
        let resolver = RootPathResolver(homeDirectory: "")
        var seen: Set<String> = []
        return output.components(separatedBy: "\n").compactMap { line in
            let path = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
            guard path.hasPrefix("/"), !path.contains("\0"), let resolved = resolver.resolve(path), seen.insert(resolved).inserted else { return nil }
            return resolved
        }
    }

    /// stderr やエラー詳細はパスを含み得るため保持せず、分類だけを返す。
    private static func failure(from error: any Error) -> ZoxideError {
        if let error = error as? ZoxideError { return error }
        if error is CancellationError { return .cancelled }
        if case CommandRunnerError.timedOut = error { return .timedOut }
        return .launchFailed
    }

    /// 公開ログにパスを含めず、未インストールとキャンセルは通常のスキップとして debug にする。
    private func log(_ error: ZoxideError) {
        switch error {
        case .notInstalled, .cancelled:
            Log.debug("zoxide の候補取得をスキップしました")
        case .timedOut:
            Log.warning("zoxide query がタイムアウトしました")
        case .nonZeroExit(let code):
            Log.warning("zoxide query が終了コード \(code) で失敗しました")
        case .invalidDataDirectory, .databaseUnavailable, .databaseTooLarge:
            Log.warning("zoxide の履歴を読み取れませんでした")
        case .launchFailed:
            Log.warning("zoxide query を起動できませんでした")
        }
    }
}
