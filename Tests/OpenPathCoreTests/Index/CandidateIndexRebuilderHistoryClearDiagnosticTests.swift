import Testing

@testable import OpenPathCore

/// 履歴のクリアで履歴の候補をインデックスから取り除いたことの診断（実機 QA の MENU-04・MENU-05 を debug ログで判定するため）。
/// 取り除いた候補の数・反映までの時間・全件の再構築の途中だったかだけを報告し、パスは報告しない。
@MainActor
@Suite("CandidateIndexRebuilder: 履歴のクリアの診断", .timeLimit(.minutes(1)))
struct CandidateIndexRebuilderHistoryClearDiagnosticTests {
    private typealias F = RebuilderFixtures

    private static let historyPaths = ["/rebuild/history-a", "/rebuild/history-b", "/rebuild/history-c"]
    private static let rootItem = "/rebuild/first/repo"

    /// 履歴を消し、`didRemove` が呼ばれるまで待つ。
    /// - Returns: `didRemove` が呼ばれた時点で報告済みだった診断の数。
    @discardableResult
    private static func clearHistory(_ harness: RebuilderHarness) async -> Int {
        let diagnostics = harness.historyClearDiagnostics
        return await withCheckedContinuation { continuation in
            harness.rebuilder.historyDidClear {
                continuation.resume(returning: diagnostics.diagnostics.count)
            }
        }
    }

    @Test("構築を終えた後に履歴を消したら、取り除いた履歴の候補の数と構築中でなかったことを、クエリに反映した後・didRemove の前に報告する")
    func reportsRemovalAfterBuild() async {
        let harness = RebuilderHarness()
        harness.source(.history).setSnapshot(items: Self.historyPaths.map(F.directory))
        harness.source(.root(F.firstRoot)).setSnapshot(items: [F.directory(Self.rootItem)])
        await harness.startAndWait()

        let reportedAtDidRemove = await Self.clearHistory(harness)

        let diagnostics = harness.historyClearDiagnostics.diagnostics
        #expect(reportedAtDidRemove == 1)
        #expect(diagnostics.map(\.removedCount) == [Self.historyPaths.count])
        #expect(diagnostics.map(\.wasRebuilding) == [false])
    }

    @Test("全件の再構築の途中で履歴を消したら、構築中だったことを報告する（MENU-05）")
    func reportsRebuildingWhenClearedDuringBuild() async throws {
        let harness = RebuilderHarness()
        let history = harness.source(.history)
        let root = harness.source(.root(F.firstRoot))
        history.setSnapshot(items: [F.directory(Self.historyPaths[0])])
        root.setGated(true)
        harness.rebuilder.start()
        await root.waitUntilStarted(count: 1)
        let hasHistory = try await F.eventually { try await harness.indexedPaths() == [Self.historyPaths[0]] }

        await Self.clearHistory(harness)
        root.release(items: [F.directory(Self.rootItem)])
        await harness.waitUntilIdle()

        #expect(hasHistory)
        let diagnostics = harness.historyClearDiagnostics.diagnostics
        #expect(diagnostics.map(\.removedCount) == [1])
        #expect(diagnostics.map(\.wasRebuilding) == [true])
    }

    @Test("続けて消したら、2 回目は取り除いた候補が 0 件と報告する")
    func reportsZeroOnRepeatedClear() async {
        let harness = RebuilderHarness()
        harness.source(.history).setSnapshot(items: Self.historyPaths.map(F.directory))
        await harness.startAndWait()

        await Self.clearHistory(harness)
        await Self.clearHistory(harness)

        #expect(harness.historyClearDiagnostics.diagnostics.map(\.removedCount) == [Self.historyPaths.count, 0])
    }

    @Test("CandidateIndex は、無効にしたときに取り除いたソースの候補の数を返す")
    func indexReportsRemovedCount() async {
        let index = CandidateIndex(fileExistence: RecordingFileExistenceChecker(), now: { IndexFixtures.now }, history: { [] })
        await index.replace(source: .history, with: Self.historyPaths.map(F.directory))
        await index.replace(source: .root(F.firstRoot), with: [F.directory(Self.rootItem)])

        let first = index.invalidateCountingRemoved(source: .history)
        await first.publication.value
        let second = index.invalidateCountingRemoved(source: .history)
        await second.publication.value

        #expect(first.removedCount == Self.historyPaths.count)
        #expect(second.removedCount == 0)
        #expect(index.count == 1)
    }

    @Test("文言は取り除いた数・時間・構築中かだけを含み、パスとログを読むスクリプトの目印を含まない")
    func message() {
        let diagnostic = HistoryClearDiagnostic(removedCount: 12, elapsed: .milliseconds(3), wasRebuilding: true)

        #expect(diagnostic.logMessage == "history clear removed (candidates: 12, elapsed: 3ms, rebuilding: true)")
        #expect(DiagnosticLogContract.isSafe(diagnostic.logMessage))
    }
}
