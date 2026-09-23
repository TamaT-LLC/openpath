import Testing

import OpenPathCore

/// 既定の config.toml を生成するときに使う `root()`（UX-001 §7）。
@Suite("GhqRepositoryLister.root")
struct GhqRepositoryListerRootTests {
    private typealias F = GhqFixtures

    @Test("ghq root だけを実行し、出力の 1 行目を返す（ghq list は実行しない）")
    func returnsRootWithoutListing() async {
        let runner = F.makeRunner(rootOutput: "\(F.ghqRoot)\n", listOutput: "")
        let lister = F.makeLister(runner: runner)

        let root = await lister.root()

        #expect(root == F.ghqRoot)
        #expect(await runner.invocations == [F.invocation(F.rootArguments)])
    }

    @Test("ConfigStore に ghq root の取得元として渡せる")
    func conformsToGhqRootProviding() async {
        let runner = F.makeRunner(listOutput: "")
        let provider: any GhqRootProviding = F.makeLister(runner: runner)

        #expect(await provider.root() == F.ghqRoot)
    }

    @Test("無効化されていれば何も実行せず nil")
    func returnsNilWhenDisabled() async {
        let runner = F.makeRunner(listOutput: "")
        let searchPathProvider = SearchPathProviderSpy(path: F.searchPath)
        let lister = F.makeLister(runner: runner, isEnabled: false, searchPathProvider: searchPathProvider)

        #expect(await lister.root() == nil)
        #expect(await runner.invocations.isEmpty)
        #expect(await searchPathProvider.callCount == 0)
    }

    @Test("未インストールなら nil")
    func returnsNilWhenNotInstalled() async {
        let runner = F.makeRunner(listOutput: "")
        let lister = F.makeLister(runner: runner, installedDirectory: nil)

        #expect(await lister.root() == nil)
        #expect(await runner.invocations.isEmpty)
    }

    @Test("非ゼロ終了なら nil")
    func returnsNilOnNonZeroExit() async {
        let runner = CommandRunnerMock { _ in
            CommandResult(exitCode: F.failureExitCode, standardOutput: "", standardError: "error")
        }
        let lister = F.makeLister(runner: runner)

        #expect(await lister.root() == nil)
    }

    @Test("起動に失敗したら nil")
    func returnsNilOnLaunchFailure() async {
        let runner = CommandRunnerMock { invocation in
            throw CommandRunnerError.launchFailed(executable: invocation.executable, reason: "failed")
        }
        let lister = F.makeLister(runner: runner)

        #expect(await lister.root() == nil)
    }

    @Test("出力が空白だけなら nil")
    func returnsNilOnEmptyOutput() async {
        let runner = F.makeRunner(rootOutput: " \n\n", listOutput: "")
        let lister = F.makeLister(runner: runner)

        #expect(await lister.root() == nil)
    }
}
