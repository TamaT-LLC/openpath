import os

@testable import OpenPathCore

/// 設定から ScriptedCandidateSource を組み立てる CandidateSourceProviding。
/// 同じ kind には常に同じソースを返すため、設定が変わっても kind ごとの呼び出しを追える。
/// 並びは本番（StandardCandidateSources）と同じく history → roots → ghq。
final class ScriptedSourceProvider: CandidateSourceProviding {
    private let sources = OSAllocatedUnfairLock<[CandidateSourceKind: ScriptedCandidateSource]>(initialState: [:])

    /// `kind` のソース。まだ無ければ空の候補を返すソースを作る
    func source(_ kind: CandidateSourceKind) -> ScriptedCandidateSource {
        sources.withLock { sources in
            if let source = sources[kind] {
                return source
            }
            let source = ScriptedCandidateSource(kind: kind)
            sources[kind] = source
            return source
        }
    }

    func sources(for config: Config) -> [any CandidateSource] {
        let roots: [any CandidateSource] = config.roots.map { source(.root($0)) }
        let ghq: [any CandidateSource] = config.ghq.enabled ? [source(.ghq)] : []
        return [source(.history)] + roots + ghq
    }
}

/// CandidateIndexRebuilder のテストで共有する値と組み立て。
enum RebuilderFixtures {
    static let firstRoot = "/rebuild/first"
    static let secondRoot = "/rebuild/second"
    static let interval = CandidateIndexRebuilder.defaultInterval
    /// 周期の境界の直前・直後を表すための僅かな時間
    static let tick: Duration = .seconds(1)

    static func config(roots: [String] = [firstRoot], ghq: Bool = false) -> Config {
        Config(roots: roots, ghq: GhqConfig(enabled: ghq))
    }

    static func directory(_ path: String) -> SourceItem {
        SourceItem(path: path, isDirectory: true)
    }

    /// 別のスレッドで進む処理の結果を、条件が満たされるか上限の時間が過ぎるまで待つ。満たされたかを返す
    @MainActor
    static func eventually(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async throws -> Bool
    ) async rethrows -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return try await condition()
    }
}

/// CandidateIndexRebuilder と、その依存（CandidateIndex・ソース・時計）の組み。
@MainActor
struct RebuilderHarness {
    /// 空クエリで全件を見るための上限（テストの候補は空クエリの上限 8 件に収まる件数にする）
    private static let allLimit = CandidateIndex.emptyQueryLimit

    let index: CandidateIndex
    let provider = ScriptedSourceProvider()
    let scheduleClock = ScheduleTestClock()
    let rebuilder: CandidateIndexRebuilder

    init(config: Config = RebuilderFixtures.config()) {
        let index = CandidateIndex(fileExistence: RecordingFileExistenceChecker(), now: { IndexFixtures.now }, history: { [] })
        self.index = index
        rebuilder = CandidateIndexRebuilder(
            index: index,
            config: config,
            sourceProvider: provider,
            clock: scheduleClock
        )
    }

    func source(_ kind: CandidateSourceKind) -> ScriptedCandidateSource {
        provider.source(kind)
    }

    /// インデックスにある候補のパス（昇順）
    func indexedPaths() async throws -> [String] {
        try await index.query("", directoriesOnly: false, limit: Self.allLimit).map(\.candidate.path).sorted()
    }

    /// 進行中と後続の再構築がすべて終わるまで待つ
    func waitUntilIdle() async {
        await rebuilder.waitUntilIdle()
    }

    /// 起動時の再構築を終えた状態にする
    func startAndWait() async {
        rebuilder.start()
        await rebuilder.waitUntilIdle()
    }
}
