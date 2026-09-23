import Testing

import OpenPathCore

/// 設定の変更による再構築（FR-CONFIG-01、DSN-002 §3・§6）。
@MainActor
@Suite("CandidateIndexRebuilder: 設定の変更", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderConfigTests {
    private typealias F = RebuilderFixtures

    /// 候補ソースに関わる設定を 1 つだけ変えた設定
    enum SourceSettingChange: CaseIterable, CustomTestStringConvertible {
        case roots
        case depth
        case includeFiles
        case ignore
        case ghq

        var testDescription: String {
            switch self {
            case .roots: "roots"
            case .depth: "depth"
            case .includeFiles: "include_files"
            case .ignore: "ignore"
            case .ghq: "ghq.enabled"
            }
        }

        func applied(to base: Config) -> Config {
            Config(
                roots: self == .roots ? base.roots + [F.secondRoot] : base.roots,
                depth: self == .depth ? base.depth + 1 : base.depth,
                includeFiles: self == .includeFiles ? !base.includeFiles : base.includeFiles,
                ignore: self == .ignore ? base.ignore + ["vendor"] : base.ignore,
                ghq: self == .ghq ? GhqConfig(enabled: !base.ghq.enabled) : base.ghq
            )
        }
    }

    @Test("候補ソースに関わる設定が変わると、全ソースを走査し直す", arguments: SourceSettingChange.allCases)
    func sourceSettingChangeTriggersRebuild(change: SourceSettingChange) async {
        let base = F.config()
        let harness = RebuilderHarness(config: base)
        await harness.startAndWait()

        harness.rebuilder.apply(config: change.applied(to: base))
        await harness.waitUntilIdle()

        #expect(harness.source(.history).startedCount == 2)
        #expect(harness.source(.root(F.firstRoot)).startedCount == 2)
    }

    @Test("候補ソースに関わらない設定（hotkey・auto_confirm・disabled_apps）の変更では走査し直さない")
    func unrelatedSettingChangeDoesNotRebuild() async {
        let base = F.config()
        let harness = RebuilderHarness(config: base)
        await harness.startAndWait()

        let changed = Config(
            roots: base.roots,
            autoConfirm: !base.autoConfirm,
            hotkey: Hotkey(key: .p, modifiers: [.command, .shift]),
            disabledApps: ["com.example.editor"],
            ghq: base.ghq
        )
        harness.rebuilder.apply(config: changed)
        await harness.waitUntilIdle()

        #expect(harness.source(.root(F.firstRoot)).startedCount == 1)
        #expect(!harness.rebuilder.isRebuilding)
    }

    @Test("roots から外したルートの候補は取り除き、そのルートは走査しない")
    func removedRootIsDropped() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        harness.source(.root(F.firstRoot)).setSnapshot(items: [F.directory("/rebuild/first/a")])
        harness.source(.root(F.secondRoot)).setSnapshot(items: [F.directory("/rebuild/second/b")])
        await harness.startAndWait()
        #expect(try await harness.indexedPaths() == ["/rebuild/first/a", "/rebuild/second/b"])

        harness.rebuilder.apply(config: F.config(roots: [F.firstRoot]))
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/a"])
        #expect(harness.source(.root(F.secondRoot)).startedCount == 1)
    }

    @Test("roots を空にすると roots の候補はすべて消え、履歴は残る")
    func emptyRootsDropsAllRootCandidates() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        harness.source(.history).setSnapshot(items: [F.directory("/rebuild/history")])
        harness.source(.root(F.firstRoot)).setSnapshot(items: [F.directory("/rebuild/first/a")])
        harness.source(.root(F.secondRoot)).setSnapshot(items: [F.directory("/rebuild/second/b")])
        await harness.startAndWait()

        harness.rebuilder.apply(config: F.config(roots: []))
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/history"])
    }

    @Test("ghq を無効にすると ghq の候補を取り除き、ghq を実行しない")
    func disablingGhqDropsGhqCandidates() async throws {
        let harness = RebuilderHarness(config: F.config(ghq: true))
        harness.source(.root(F.firstRoot)).setSnapshot(items: [F.directory("/rebuild/first/a")])
        harness.source(.ghq).setSnapshot(items: [F.directory("/rebuild/ghq/repo")])
        await harness.startAndWait()
        #expect(try await harness.indexedPaths() == ["/rebuild/first/a", "/rebuild/ghq/repo"])

        harness.rebuilder.apply(config: F.config(ghq: false))
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/a"])
        #expect(harness.source(.ghq).startedCount == 1)
    }

    @Test("ghq を有効に戻すと ghq の候補を再び集める")
    func reenablingGhqCollectsAgain() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [], ghq: false))
        harness.source(.ghq).setSnapshot(items: [F.directory("/rebuild/ghq/repo")])
        await harness.startAndWait()
        #expect(harness.source(.ghq).startedCount == 0)

        harness.rebuilder.apply(config: F.config(roots: [], ghq: true))
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/ghq/repo"])
    }

    @Test("走査中に設定が変わると、走査を取り消して新しい設定で走査し直す。取り消した走査の結果では差し替えない")
    func settingChangeDuringRebuildRestartsWithNewConfig() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot, F.secondRoot]))
        let first = harness.source(.root(F.firstRoot))
        let second = harness.source(.root(F.secondRoot))
        first.setSnapshot(items: [F.directory("/rebuild/first/old")])
        second.setSnapshot(items: [F.directory("/rebuild/second/old")])
        await harness.startAndWait()
        first.setGated(true)
        second.setGated(true)
        harness.rebuilder.rebuild()
        await first.waitUntilStarted(count: 2)
        await second.waitUntilStarted(count: 2)

        harness.rebuilder.apply(config: F.config(roots: [F.firstRoot]))
        await first.waitUntilStarted(count: 3)
        // 走査し直している間も、取り消した走査の前の候補で答える
        #expect(try await harness.indexedPaths() == ["/rebuild/first/old"])
        first.release(items: [F.directory("/rebuild/first/new")])
        await harness.waitUntilIdle()

        #expect(try await harness.indexedPaths() == ["/rebuild/first/new"])
        #expect(first.cancelledCount == 1)
        #expect(second.cancelledCount == 1)
        #expect(second.startedCount == 2)
        #expect(first.maxRunningCount == 1)
    }

    @Test("start の前に渡した設定で起動時の再構築を行う")
    func configAppliedBeforeStartIsUsed() async throws {
        let harness = RebuilderHarness(config: F.config(roots: [F.firstRoot]))
        harness.source(.root(F.secondRoot)).setSnapshot(items: [F.directory("/rebuild/second/b")])

        harness.rebuilder.apply(config: F.config(roots: [F.secondRoot]))
        #expect(!harness.rebuilder.isRebuilding)
        await harness.startAndWait()

        #expect(try await harness.indexedPaths() == ["/rebuild/second/b"])
        #expect(harness.source(.root(F.firstRoot)).startedCount == 0)
    }

    @Test("stop の後の設定の変更では走査しない")
    func settingChangeAfterStopIsIgnored() async {
        let harness = RebuilderHarness()
        await harness.startAndWait()
        harness.rebuilder.stop()

        harness.rebuilder.apply(config: F.config(roots: [F.secondRoot]))
        harness.rebuilder.rebuild()
        await harness.waitUntilIdle()

        #expect(harness.source(.root(F.secondRoot)).startedCount == 0)
        #expect(harness.source(.root(F.firstRoot)).startedCount == 1)
    }
}
