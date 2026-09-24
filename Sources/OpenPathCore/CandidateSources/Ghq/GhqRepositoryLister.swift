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

    /// サブコマンドの実行に共通する、ghq の実行ファイルと環境変数
    private struct Execution {
        let executable: String
        let environment: [String: String]
    }

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
            log(error)
            return GhqListing(repositoryPaths: [], failure: error)
        }
    }

    /// `ghq root` の結果を返す。既定の config.toml の roots に使う（UX-001 §7）。
    /// 無効化されている・未インストール・失敗した場合は nil（既定の roots はホームになる）。`ghq list` は実行しない。
    public func root() async -> String? {
        guard isEnabled else { return nil }
        do throws(GhqError) {
            return try await fetchRoot(using: prepareExecution())
        } catch {
            log(error)
            return nil
        }
    }

    private func fetchRepositoryPaths() async throws(GhqError) -> [String] {
        let execution = try await prepareExecution()
        let root = try await fetchRoot(using: execution)
        let listOutput = try await run(.list, executable: execution.executable, environment: execution.environment)
        return GhqOutputParser.repositoryPaths(fromListOutput: listOutput, root: root)
    }

    /// ghq の実行ファイルの場所と、ghq に渡す環境変数を決める。
    private func prepareExecution() async throws(GhqError) -> Execution {
        let searchPath = await searchPathProvider.searchPath()
        guard let executable = executableLocator.locateExecutable(named: Self.executableName, inSearchPath: searchPath) else {
            throw .notInstalled(searchPath: searchPath)
        }
        let environment = baseEnvironment.merging([Self.pathEnvironmentKey: searchPath]) { _, replacement in replacement }
        return Execution(executable: executable, environment: environment)
    }

    private func fetchRoot(using execution: Execution) async throws(GhqError) -> String {
        let rootOutput = try await run(.root, executable: execution.executable, environment: execution.environment)
        guard let root = GhqOutputParser.root(fromOutput: rootOutput) else {
            throw .emptyRoot
        }
        return root
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

    /// `GhqError` を記録する。ghq 未インストールは ghq を使わない利用者で毎回起きるフォールバックなので debug、
    /// それ以外は利用者に影響する失敗として warning にする。
    /// `reason` / `standardError` はパスやリポジトリ識別子を含み得るため、debug であっても記録しない
    /// （debugPath 以外の debug 本文もファイルにはそのまま残るため、NFR-05 の対象は debugPath のパス引数に限る）。
    private func log(_ error: GhqError) {
        switch error {
        case .notInstalled(let searchPath):
            Log.debug("ghq が見つからないため、ghq からの候補取得をスキップします")
            Log.debugPath("ghq が見つかりません", path: searchPath)
        case .launchFailed(let subcommand, _):
            Log.warning("\(Self.commandDescription(of: subcommand)) を起動できません")
        case .nonZeroExit(let subcommand, let exitCode, _):
            Log.warning("\(Self.commandDescription(of: subcommand)) が終了コード \(exitCode) で失敗しました")
        case .timedOut(let subcommand):
            Log.warning("\(Self.commandDescription(of: subcommand)) がタイムアウトしました")
        case .emptyRoot:
            Log.warning("ghq root の出力が空でした")
        case .cancelled:
            Log.debug("ghq の呼び出しがキャンセルされました")
        }
    }

    private static func commandDescription(of subcommand: GhqSubcommand) -> String {
        (["ghq"] + subcommand.arguments).joined(separator: " ")
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
