import Foundation

/// ghq 管理下のリポジトリの絶対パス一覧を取得する（FR-SOURCE-03）。
///
/// `ghq root` → `ghq list -p` の順に実行する。GUI アプリには PATH が通っていないため、
/// ghq の場所と ghq に渡す PATH（`ghq root` は内部で git を呼ぶ）は SearchPathProviding から得る。
/// 失敗してもエラーは投げず、空の一覧と失敗理由を返す。
/// 実行するのはローカルを走査するサブコマンドだけで、ネットワーク通信はしない（NFR-01）。
public struct GhqRepositoryLister: Sendable {
    /// ghq の各サブコマンドの応答を待つ上限。`ghq list` はリポジトリ数に応じてディレクトリを走査するため長めにとる。
    public static let defaultCommandTimeout: Duration = .seconds(10)
    private static let executableName = "ghq"
    private static let pathEnvironmentKey = "PATH"

    private let isEnabled: Bool
    private let runner: any CommandRunning
    private let searchPathProvider: any SearchPathProviding
    private let executableLocator: any ExecutableLocating
    private let baseEnvironment: [String: String]
    private let commandTimeout: Duration

    /// - Parameters:
    ///   - isEnabled: 設定 `ghq.enabled`。false なら PATH の取得も含めて何も実行しない。
    ///   - runner: ghq の実行に使う。
    ///   - searchPathProvider: ghq を探す検索パスと、ghq に渡す PATH を得る。login shell の起動を繰り返さないよう共有すること。
    ///   - executableLocator: 検索パスから ghq を探す。
    ///   - baseEnvironment: ghq に渡す環境変数の元。PATH だけ検索パスに差し替える。
    ///   - commandTimeout: ghq の各サブコマンドの応答を待つ上限。
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

    /// リポジトリの絶対パス一覧を取得する。失敗時は空の一覧と失敗理由を返す。
    public func listRepositories() async -> GhqListing {
        guard isEnabled else {
            return GhqListing(repositoryPaths: [], failure: nil)
        }
        do throws(GhqError) {
            return GhqListing(repositoryPaths: try await fetchRepositoryPaths(), failure: nil)
        } catch {
            // TODO(#3): Log が main に入ったら、失敗理由を警告ログに出す
            return GhqListing(repositoryPaths: [], failure: error)
        }
    }

    private func fetchRepositoryPaths() async throws(GhqError) -> [String] {
        let searchPath = await searchPathProvider.searchPath()
        guard let executable = executableLocator.locateExecutable(named: Self.executableName, inSearchPath: searchPath) else {
            throw .notInstalled(searchPath: searchPath)
        }
        let environment = baseEnvironment.merging([Self.pathEnvironmentKey: searchPath]) { _, replacement in replacement }

        let rootOutput = try await run(.root, executable: executable, environment: environment)
        guard let root = GhqOutputParser.root(fromOutput: rootOutput) else {
            throw .emptyRoot
        }
        let listOutput = try await run(.list, executable: executable, environment: environment)
        return GhqOutputParser.repositoryPaths(fromListOutput: listOutput, root: root)
    }

    /// サブコマンドを実行して標準出力を返す。
    private func run(
        _ subcommand: GhqSubcommand,
        executable: String,
        environment: [String: String]
    ) async throws(GhqError) -> String {
        let result: CommandResult
        do {
            result = try await runner.run(
                executable: executable,
                arguments: subcommand.arguments,
                environment: environment,
                timeout: commandTimeout
            )
        } catch {
            throw Self.ghqError(from: error, running: subcommand)
        }
        guard result.exitCode == 0 else {
            let standardError = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw .nonZeroExit(subcommand, exitCode: result.exitCode, standardError: standardError)
        }
        return result.standardOutput
    }

    private static func ghqError(from error: any Error, running subcommand: GhqSubcommand) -> GhqError {
        switch error {
        case CommandRunnerError.launchFailed(_, let reason):
            .launchFailed(subcommand, reason: reason)
        case CommandRunnerError.timedOut:
            .timedOut(subcommand)
        case is CancellationError:
            .cancelled
        default:
            .launchFailed(subcommand, reason: String(describing: error))
        }
    }
}
