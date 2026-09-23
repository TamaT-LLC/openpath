import Testing

import OpenPathCore

@Suite("GhqCandidateSource")
struct GhqCandidateSourceTests {
    private typealias F = GhqFixtures

    private static let repositoryA = "/Users/me/ghq/github.com/alice/a"
    private static let repositoryB = "/Users/me/ghq/github.com/bob/b"

    @Test("kind は .ghq")
    func kindIsGhq() {
        let source = GhqCandidateSource(lister: F.makeLister(runner: F.makeRunner(listOutput: "")))

        #expect(source.kind == .ghq)
    }

    @Test("ghq のリポジトリをすべてディレクトリとして返す")
    func returnsRepositoriesAsDirectories() async throws {
        let runner = F.makeRunner(listOutput: "\(Self.repositoryA)\n\(Self.repositoryB)\n")
        let source = GhqCandidateSource(lister: F.makeLister(runner: runner))

        let snapshot = try await source.snapshot()

        #expect(snapshot == CandidateSourceSnapshot(items: [.directory(Self.repositoryA), .directory(Self.repositoryB)]))
    }

    @Test("ghq が未インストールなど取得に失敗したら、エラーにせず空の候補と ghqFailed の警告を返す")
    func returnsWarningOnFailure() async throws {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let source = GhqCandidateSource(lister: F.makeLister(runner: runner, installedDirectory: nil))

        let snapshot = try await source.snapshot()

        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.ghqFailed(.notInstalled(searchPath: F.searchPath))])
    }

    @Test("ghq.enabled = false なら空の候補を警告なしで返す")
    func returnsEmptyWhenDisabled() async throws {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let source = GhqCandidateSource(lister: F.makeLister(runner: runner, isEnabled: false))

        let snapshot = try await source.snapshot()

        #expect(snapshot == CandidateSourceSnapshot(items: []))
    }

    @Test("ghq の実行中にキャンセルされたら CancellationError を投げる")
    func throwsWhenListingIsCancelled() async {
        let runner = CommandRunnerMock { _ in throw CancellationError() }
        let source = GhqCandidateSource(lister: F.makeLister(runner: runner))

        await #expect(throws: CancellationError.self) {
            try await source.snapshot()
        }
    }

    @Test("キャンセルされたタスクから呼ぶと、一覧を取得できても CancellationError を投げる")
    func throwsWhenTaskIsCancelled() async {
        let runner = F.makeRunner(listOutput: Self.repositoryA)
        let source = GhqCandidateSource(lister: F.makeLister(runner: runner))

        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try await source.snapshot() }
        }
    }
}
