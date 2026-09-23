import Testing

import OpenPathCore

@Suite("GhqRepositoryLister")
struct GhqRepositoryListerTests {
    private typealias F = GhqFixtures

    private static let repositoryA = "/Users/me/ghq/github.com/alice/a"
    private static let repositoryB = "/Users/me/ghq/github.com/bob/b"
    private static let standardErrorMessage = "error: something went wrong"
    private static let launchFailureReason = "The file “ghq” doesn’t exist."

    /// 指定のサブコマンドだけ handler の応答に差し替え、それ以外は正常に応答するモック。
    private static func makeRunner(
        failing failingArguments: [String],
        with response: @escaping @Sendable () throws -> CommandResult
    ) -> CommandRunnerMock {
        CommandRunnerMock { invocation in
            if invocation.arguments == failingArguments {
                return try response()
            }
            switch invocation.arguments {
            case F.rootArguments:
                return .succeeded(output: F.ghqRoot + "\n")
            case F.listArguments:
                return .succeeded(output: repositoryA + "\n")
            default:
                throw CommandRunnerMock.UnexpectedInvocation(invocation: invocation)
            }
        }
    }

    // MARK: - 正常系

    @Test("ghq root → ghq list -p の順に実行し、リポジトリの絶対パス一覧を返す")
    func listsRepositoriesViaRootAndList() async {
        let runner = F.makeRunner(listOutput: "\(Self.repositoryA)\n\(Self.repositoryB)\n")
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing.repositoryPaths == [Self.repositoryA, Self.repositoryB])
        #expect(listing.failure == nil)
        #expect(await runner.invocations == [
            F.invocation(F.rootArguments),
            F.invocation(F.listArguments),
        ])
    }

    @Test("ghq には元の環境変数を引き継ぎつつ PATH だけ login shell 由来の検索パスに差し替えて渡す")
    func passesSearchPathAsEnvironment() async throws {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let lister = F.makeLister(runner: runner)

        _ = await lister.listRepositories()

        let environment = try #require(await runner.invocations.first?.environment)
        #expect(environment["PATH"] == F.searchPath)
        #expect(environment["HOME"] == F.baseEnvironment["HOME"])
        #expect(environment["LANG"] == F.baseEnvironment["LANG"])
    }

    @Test("既定のタイムアウトは数秒以上に設定されている")
    func defaultCommandTimeoutIsSeconds() {
        #expect(GhqRepositoryLister.defaultCommandTimeout >= .seconds(1))
    }

    // MARK: - 無効化・未インストール

    @Test("ghq.enabled = false のときは PATH 取得も含めコマンドを一切実行せず空を返す")
    func disabledRunsNothing() async {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let searchPathProvider = SearchPathProviderSpy(path: F.searchPath)
        let lister = F.makeLister(runner: runner, isEnabled: false, searchPathProvider: searchPathProvider)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: nil))
        #expect(await runner.invocations.isEmpty)
        #expect(await searchPathProvider.callCount == 0)
    }

    @Test("ghq が検索パス上に無い（未インストール）ときはコマンドを実行せず空と notInstalled を返す")
    func notInstalledReturnsEmpty() async {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let lister = F.makeLister(runner: runner, installedDirectory: nil)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: .notInstalled(searchPath: F.searchPath)))
        #expect(await runner.invocations.isEmpty)
    }

    // MARK: - 失敗

    @Test("ghq root が非ゼロ終了したら ghq list -p は実行せず空と nonZeroExit を返す")
    func rootNonZeroExitReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.rootArguments) {
            CommandResult(exitCode: F.failureExitCode, standardOutput: "", standardError: Self.standardErrorMessage + "\n")
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(
            repositoryPaths: [],
            failure: .nonZeroExit(.root, exitCode: F.failureExitCode, standardError: Self.standardErrorMessage)
        ))
        #expect(await runner.invocations == [F.invocation(F.rootArguments)])
    }

    @Test("ghq list -p が非ゼロ終了したら、途中まで出力があっても空と nonZeroExit を返す")
    func listNonZeroExitReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.listArguments) {
            CommandResult(
                exitCode: F.failureExitCode,
                standardOutput: Self.repositoryA + "\n",
                standardError: Self.standardErrorMessage
            )
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(
            repositoryPaths: [],
            failure: .nonZeroExit(.list, exitCode: F.failureExitCode, standardError: Self.standardErrorMessage)
        ))
    }

    @Test("ghq list -p がタイムアウトしたら空と timedOut を返す")
    func listTimeoutReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.listArguments) {
            throw CommandRunnerError.timedOut(executable: F.ghqExecutable, timeout: F.commandTimeout)
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: .timedOut(.list)))
    }

    @Test("ghq root がタイムアウトしたら ghq list -p は実行せず空と timedOut を返す")
    func rootTimeoutReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.rootArguments) {
            throw CommandRunnerError.timedOut(executable: F.ghqExecutable, timeout: F.commandTimeout)
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: .timedOut(.root)))
        #expect(await runner.invocations == [F.invocation(F.rootArguments)])
    }

    @Test("ghq を起動できなかったら空と launchFailed を返す")
    func launchFailureReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.rootArguments) {
            throw CommandRunnerError.launchFailed(executable: F.ghqExecutable, reason: Self.launchFailureReason)
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(
            repositoryPaths: [],
            failure: .launchFailed(.root, reason: Self.launchFailureReason)
        ))
    }

    @Test("実行中にキャンセルされたら空と cancelled を返す")
    func cancellationReturnsEmpty() async {
        let runner = Self.makeRunner(failing: F.listArguments) {
            throw CancellationError()
        }
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: .cancelled))
    }

    @Test("ghq root の出力が空なら ghq list -p は実行せず空と emptyRoot を返す")
    func emptyRootReturnsEmpty() async {
        let runner = F.makeRunner(rootOutput: " \n", listOutput: Self.repositoryA)
        let lister = F.makeLister(runner: runner)

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [], failure: .emptyRoot))
        #expect(await runner.invocations == [F.invocation(F.rootArguments)])
    }

    // MARK: - PATH 取得との結合

    @Test("login shell から PATH を取得できないときは既定 PATH から ghq を探して実行する")
    func fallsBackToDefaultSearchPath() async {
        let fallbackPath = LoginShellPathResolver.defaultFallbackSearchPath
        let runner = CommandRunnerMock { invocation in
            switch invocation.arguments {
            case LoginShellPathResolver.printPathArguments:
                throw CommandRunnerError.timedOut(executable: invocation.executable, timeout: invocation.timeout)
            case F.rootArguments:
                return .succeeded(output: F.ghqRoot)
            case F.listArguments:
                return .succeeded(output: Self.repositoryA)
            default:
                throw CommandRunnerMock.UnexpectedInvocation(invocation: invocation)
            }
        }
        let lister = F.makeLister(runner: runner, searchPathProvider: LoginShellPathResolver(runner: runner))

        let listing = await lister.listRepositories()

        #expect(listing == GhqListing(repositoryPaths: [Self.repositoryA], failure: nil))
        let ghqInvocations = await runner.invocations.filter { $0.executable == F.ghqExecutable }
        #expect(ghqInvocations.map(\.arguments) == [F.rootArguments, F.listArguments])
        #expect(ghqInvocations.allSatisfy { $0.environment?["PATH"] == fallbackPath })
    }
}
