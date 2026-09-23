import Testing

import OpenPathCore

@Suite("LoginShellPathResolver")
struct LoginShellPathResolverTests {
    private static let shellPath = "/bin/zsh"
    private static let timeout: Duration = .milliseconds(1_500)
    private static let loginPath = "/Users/me/bin:/opt/homebrew/bin:/usr/bin:/bin"
    /// loginPath にすべて含まれる既定 PATH。補完の影響を受けずに取得結果を確かめるために使う。
    private static let coveredFallbackPath = "/opt/homebrew/bin:/usr/bin:/bin"
    private static let failureExitCode: Int32 = 1
    /// 同時呼び出しの検証で、1 回目の実行中に 2 回目が届くよう応答を遅らせる時間。
    private static let responseDelay: Duration = .milliseconds(50)

    private static func makeResolver(
        runner: CommandRunnerMock,
        fallbackSearchPath: String = coveredFallbackPath
    ) -> LoginShellPathResolver {
        LoginShellPathResolver(
            runner: runner,
            shellPath: shellPath,
            timeout: timeout,
            fallbackSearchPath: fallbackSearchPath
        )
    }

    private static func makeRunner(output: String) -> CommandRunnerMock {
        CommandRunnerMock { _ in .succeeded(output: output) }
    }

    // MARK: - 取得

    @Test("login shell（zsh -lc 'echo $PATH'）を指定のタイムアウトで実行し、その PATH を返す")
    func resolvesPathFromLoginShell() async {
        let runner = Self.makeRunner(output: Self.loginPath + "\n")
        let resolver = Self.makeResolver(runner: runner)

        let path = await resolver.searchPath()

        #expect(path == Self.loginPath)
        #expect(await runner.invocations == [
            CommandRunnerMock.Invocation(
                executable: Self.shellPath,
                arguments: ["-lc", "echo $PATH"],
                environment: nil,
                timeout: Self.timeout
            ),
        ])
    }

    @Test("既定では /bin/zsh を数秒のタイムアウトで実行する")
    func usesZshWithSecondsTimeoutByDefault() async throws {
        let runner = Self.makeRunner(output: Self.loginPath)
        let resolver = LoginShellPathResolver(runner: runner)

        _ = await resolver.searchPath()

        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.executable == Self.shellPath)
        #expect(invocation.arguments == LoginShellPathResolver.printPathArguments)
        #expect(invocation.timeout == LoginShellPathResolver.defaultTimeout)
        #expect(LoginShellPathResolver.defaultTimeout >= .seconds(1))
        #expect(LoginShellPathResolver.defaultTimeout <= .seconds(10))
    }

    @Test("起動時のメッセージなどが先に出力されても最後の行を PATH とみなす")
    func usesLastNonEmptyLine() async {
        let runner = Self.makeRunner(output: "Welcome!\nLast login: today\n\(Self.loginPath)\n\n")
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == Self.loginPath)
    }

    @Test("空のエントリ・相対パスのエントリ・重複を取り除く")
    func sanitizesEntries() async {
        let runner = Self.makeRunner(output: "/opt/homebrew/bin::relative/bin:/usr/bin:./x:/opt/homebrew/bin:/bin:")
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == "/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test("login shell の PATH に無い既定ディレクトリは末尾に補う")
    func appendsMissingFallbackDirectories() async {
        let runner = Self.makeRunner(output: "/Users/me/bin:/usr/bin")
        let resolver = Self.makeResolver(runner: runner, fallbackSearchPath: "/opt/homebrew/bin:/usr/bin:/bin")

        #expect(await resolver.searchPath() == "/Users/me/bin:/usr/bin:/opt/homebrew/bin:/bin")
    }

    // MARK: - キャッシュ

    @Test("2 回目以降は login shell を再実行せずキャッシュを返す")
    func cachesResolvedPath() async {
        let runner = Self.makeRunner(output: Self.loginPath)
        let resolver = Self.makeResolver(runner: runner)

        let first = await resolver.searchPath()
        let second = await resolver.searchPath()

        #expect(first == Self.loginPath)
        #expect(second == Self.loginPath)
        #expect(await runner.invocations.count == 1)
    }

    @Test("同時に問い合わせても login shell は 1 回だけ実行する")
    func runsLoginShellOnceForConcurrentCalls() async {
        let runner = CommandRunnerMock { _ in
            try await Task.sleep(for: Self.responseDelay)
            return .succeeded(output: Self.loginPath)
        }
        let resolver = Self.makeResolver(runner: runner)

        async let first = resolver.searchPath()
        async let second = resolver.searchPath()
        let paths = await [first, second]

        #expect(paths == [Self.loginPath, Self.loginPath])
        #expect(await runner.invocations.count == 1)
    }

    // MARK: - フォールバック

    @Test("login shell が非ゼロ終了したら既定 PATH にフォールバックする")
    func fallsBackOnNonZeroExit() async {
        let runner = CommandRunnerMock { _ in
            CommandResult(exitCode: Self.failureExitCode, standardOutput: Self.loginPath, standardError: "zsh: error")
        }
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == Self.coveredFallbackPath)
    }

    @Test("login shell がタイムアウトしたら既定 PATH にフォールバックする")
    func fallsBackOnTimeout() async {
        let runner = CommandRunnerMock { invocation in
            throw CommandRunnerError.timedOut(executable: invocation.executable, timeout: invocation.timeout)
        }
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == Self.coveredFallbackPath)
    }

    @Test("login shell を起動できなかったら既定 PATH にフォールバックする")
    func fallsBackOnLaunchFailure() async {
        let runner = CommandRunnerMock { invocation in
            throw CommandRunnerError.launchFailed(executable: invocation.executable, reason: "not found")
        }
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == Self.coveredFallbackPath)
    }

    @Test("出力が空、または絶対パスのエントリが 1 つも無ければ既定 PATH にフォールバックする", arguments: [
        "",
        "\n  \n",
        "relative/bin:.",
    ])
    func fallsBackOnUnusableOutput(output: String) async {
        let runner = Self.makeRunner(output: output)
        let resolver = Self.makeResolver(runner: runner)

        #expect(await resolver.searchPath() == Self.coveredFallbackPath)
    }

    @Test("フォールバックした結果もキャッシュし、login shell を再実行しない")
    func cachesFallbackPath() async {
        let runner = CommandRunnerMock { invocation in
            throw CommandRunnerError.timedOut(executable: invocation.executable, timeout: invocation.timeout)
        }
        let resolver = Self.makeResolver(runner: runner)

        _ = await resolver.searchPath()
        let second = await resolver.searchPath()

        #expect(second == Self.coveredFallbackPath)
        #expect(await runner.invocations.count == 1)
    }

    @Test("既定 PATH には Homebrew（Apple Silicon / Intel）とシステムのディレクトリが含まれる")
    func defaultFallbackContainsCommonDirectories() {
        let directories = LoginShellPathResolver.defaultFallbackSearchPath.split(separator: ":").map(String.init)

        #expect(directories.contains("/opt/homebrew/bin"))
        #expect(directories.contains("/usr/local/bin"))
        #expect(directories.contains("/usr/bin"))
        #expect(directories.contains("/bin"))
    }
}
