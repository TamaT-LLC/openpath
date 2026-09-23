import OpenPathCore

/// ghq 関連テストで共有する固定値と組み立て処理。
enum GhqFixtures {
    static let installedDirectory = "/opt/homebrew/bin"
    static let ghqExecutable = "/opt/homebrew/bin/ghq"
    static let searchPath = "/Users/me/bin:/opt/homebrew/bin:/usr/bin:/bin"
    static let ghqRoot = "/Users/me/ghq"
    static let commandTimeout: Duration = .seconds(7)
    static let rootArguments = ["root"]
    static let listArguments = ["list", "-p"]
    static let failureExitCode: Int32 = 1

    /// GUI アプリ起動時を想定した、PATH が最小限しか通っていない環境変数。
    static let baseEnvironment = [
        "HOME": "/Users/me",
        "LANG": "ja_JP.UTF-8",
        "PATH": "/usr/bin:/bin",
    ]

    /// ghq に渡るべき環境変数（PATH だけ検索パスに差し替わる）。
    static var ghqEnvironment: [String: String] {
        baseEnvironment.merging(["PATH": searchPath]) { _, new in new }
    }

    static func invocation(_ arguments: [String]) -> CommandRunnerMock.Invocation {
        CommandRunnerMock.Invocation(
            executable: ghqExecutable,
            arguments: arguments,
            environment: ghqEnvironment,
            timeout: commandTimeout
        )
    }

    /// `ghq root` と `ghq list -p` にそれぞれ指定の出力で成功するモック。
    static func makeRunner(rootOutput: String = ghqRoot + "\n", listOutput: String) -> CommandRunnerMock {
        CommandRunnerMock { invocation in
            switch invocation.arguments {
            case rootArguments:
                return .succeeded(output: rootOutput)
            case listArguments:
                return .succeeded(output: listOutput)
            default:
                throw CommandRunnerMock.UnexpectedInvocation(invocation: invocation)
            }
        }
    }

    static func makeLister(
        runner: CommandRunnerMock,
        isEnabled: Bool = true,
        searchPathProvider: any SearchPathProviding = SearchPathProviderSpy(path: searchPath),
        installedDirectory: String? = installedDirectory
    ) -> GhqRepositoryLister {
        GhqRepositoryLister(
            isEnabled: isEnabled,
            runner: runner,
            searchPathProvider: searchPathProvider,
            executableLocator: StubExecutableLocator(installedDirectory: installedDirectory),
            baseEnvironment: baseEnvironment,
            commandTimeout: commandTimeout
        )
    }
}
