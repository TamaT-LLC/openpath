import Darwin
import Foundation
import Testing

@testable import OpenPathCore

/// DSN-002 §8 の性能目標の簡易ベンチ。
/// - 1 文字入力ごとのクエリ（候補 5,000 件）16ms 以内
/// - 空入力時の初期表示 30ms 以内
/// - 候補 20,000 件の常駐メモリ 30MB 以下（インデックスが保持する分）
///
/// 時間は FuzzyMatcherBenchmarkTests と同じく、実行したスレッドの CPU 時間の最小値で判定する。
/// `CandidateIndex.query` は履歴を取るために MainActor へ移るため、ここではその後の同期部分
/// （履歴の表引き作成・前置フィルタ・マッチ・並べ替え・存在確認）を直接測る。
@Suite("CandidateIndex ベンチマーク", .serialized)
struct CandidateIndexBenchmarkTests {
    private struct Measurement {
        let cpuTime: Duration
        let wallTime: Duration
    }

    private static let queryCandidateCount = 5_000
    private static let residentCandidateCount = 20_000
    private static let historyCount = HistoryList.maxEntryCount
    private static let queryBudget = Duration.milliseconds(16)
    private static let emptyQueryBudget = Duration.milliseconds(30)
    private static let bytesPerMegabyte = 1_048_576.0
    private static let residentMemoryBudgetMegabytes = 30.0
    #if DEBUG
    /// デバッグビルドは最適化が効かず数倍遅いため、桁違いの退行の検知に留める。
    /// 目標値そのものの判定はリリースビルド（`./scripts/test.sh -c release`）で行う。
    private static let budgetMultiplier = 10
    #else
    private static let budgetMultiplier = 1
    #endif
    private static let measurementCount = 5
    private static let resultLimit = 50
    private static let millisecondsPerSecond = 1_000.0
    private static let attosecondsPerMillisecond = 1e15

    private static let queries = ["s", "sd", "sda", "fern", "openpath", "rgtf", "資料", "めも"]
    private static let words = [
        "openpath", "system", "doc", "agent", "fern", "config", "dotfiles", "notes",
        "api", "server", "client", "tools", "Documents", "Projects", "MyApp", "swift",
        "kit", "web", "infra", "sandbox", "design", "資料", "メモ", "playground",
    ]
    private static let owners = ["TamaT-LLC", "takehiro", "apple", "swiftlang", "junegunn", "ajeetdsouza"]

    /// ghq 配下のリポジトリと roots 配下のディレクトリ・ファイルに近い形の候補を決定的に生成する
    private static func makeItems(count: Int) -> [SourceItem] {
        (0..<count).map { index in
            let first = words[index % words.count]
            let second = words[(index / words.count) % words.count]
            let owner = owners[index % owners.count]
            let name = "\(first)-\(second)-\(index)"
            return SourceItem(path: "/Users/takehiro/repos/github.com/\(owner)/\(name)", isDirectory: index % 4 != 0)
        }
    }

    /// 候補の先頭から `count` 件を、使用回数と最終使用日時をばらして履歴にする
    private static func makeHistory(for items: [SourceItem], count: Int) -> [HistoryEntry] {
        items.prefix(count).enumerated().map { offset, item in
            HistoryEntry(path: item.path, count: offset % 7 + 1, lastUsed: IndexFixtures.ago(Double(offset) * IndexFixtures.oneHour))
        }
    }

    private static func makeCatalog(items: [SourceItem]) -> CandidateCatalog {
        CandidateCatalog(merging: [.ghq: CandidatePreparer(matcher: FuzzyMatcher()).prepare(items)])
    }

    /// 候補の前処理はデバッグビルドで 1 件 100µs 以上かかるため、テストケース間で共有する（初回に 1 度だけ作る）
    private enum Shared {
        static let queryItems = makeItems(count: queryCandidateCount)
        static let queryCatalog = makeCatalog(items: queryItems)
        static let queryHistory = makeHistory(for: queryItems, count: historyCount)
        static let residentItems = makeItems(count: residentCandidateCount)
        static let residentCatalog = makeCatalog(items: residentItems)
        static let residentHistory = makeHistory(for: residentItems, count: historyCount)
    }

    private static func measure(_ body: () throws -> Void) rethrows -> Measurement {
        let timer = ContinuousClock()
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let wallTime = try timer.measure(body)
        let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        return Measurement(cpuTime: .nanoseconds(cpuEnd - cpuStart), wallTime: wallTime)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * millisecondsPerSecond
            + Double(components.attoseconds) / attosecondsPerMillisecond
    }

    private static func heapBytesInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return statistics.size_in_use
    }

    /// 履歴の表引きの作成から存在確認までを 1 回分として、`measurementCount` 回の最小値を返す
    private static func measureQuery(
        _ query: String,
        catalog: CandidateCatalog,
        history: [HistoryEntry],
        resultCount: inout Int
    ) throws -> Measurement {
        let ranker = CandidateRanker(
            matcher: FuzzyMatcher(),
            fileExistence: RecordingFileExistenceChecker(),
            prefilterThreshold: CandidateIndex.prefilterThreshold
        )
        var count = 0
        let measurements = try (0..<measurementCount).map { _ in
            try measure {
                let lookup = HistoryLookup(entries: history, now: IndexFixtures.now, catalog: catalog)
                count = try ranker.rank(query, in: catalog, history: lookup, directoriesOnly: false, limit: resultLimit).count
            }
        }
        resultCount = count
        return Measurement(
            cpuTime: try #require(measurements.map(\.cpuTime).min()),
            wallTime: try #require(measurements.map(\.wallTime).min())
        )
    }

    @Test("候補 5,000 件 × 1 クエリが目標時間内に終わる", arguments: queries)
    func queriesWithinBudget(query: String) throws {
        let catalog = Shared.queryCatalog
        let history = Shared.queryHistory
        var resultCount = 0

        let measurement = try Self.measureQuery(query, catalog: catalog, history: history, resultCount: &resultCount)
        let limit = Self.queryBudget * Self.budgetMultiplier

        print(
            "[CandidateIndexBenchmark] query=\"\(query)\" candidates=\(catalog.entries.count) results=\(resultCount)"
                + " cpu=\(Self.milliseconds(measurement.cpuTime))ms wall=\(Self.milliseconds(measurement.wallTime))ms"
                + " limit=\(Self.milliseconds(limit))ms"
        )
        #expect(resultCount > 0)
        #expect(measurement.cpuTime <= limit)
    }

    @Test("候補 20,000 件でも空クエリの初期表示が目標時間内に終わる")
    func emptyQueryWithinBudget() throws {
        let catalog = Shared.residentCatalog
        let history = Shared.residentHistory
        var resultCount = 0

        let measurement = try Self.measureQuery("", catalog: catalog, history: history, resultCount: &resultCount)
        let limit = Self.emptyQueryBudget * Self.budgetMultiplier

        print(
            "[CandidateIndexBenchmark] empty query candidates=\(catalog.entries.count) results=\(resultCount)"
                + " cpu=\(Self.milliseconds(measurement.cpuTime))ms wall=\(Self.milliseconds(measurement.wallTime))ms"
                + " limit=\(Self.milliseconds(limit))ms"
        )
        #expect(resultCount == IndexFixtures.emptyQueryLimit)
        #expect(measurement.cpuTime <= limit)
    }

    /// 前置フィルタが効く件数での参考値。目標は 5,000 件で定められているため、上限は 5,000 件の目標の件数比とする
    @Test("候補 20,000 件（前置フィルタあり）のクエリ時間を測る", arguments: queries)
    func queriesAtResidentScale(query: String) throws {
        let catalog = Shared.residentCatalog
        let history = Shared.residentHistory
        var resultCount = 0

        let measurement = try Self.measureQuery(query, catalog: catalog, history: history, resultCount: &resultCount)
        let scale = Self.residentCandidateCount / Self.queryCandidateCount
        let limit = Self.queryBudget * scale * Self.budgetMultiplier

        print(
            "[CandidateIndexBenchmark] query=\"\(query)\" candidates=\(catalog.entries.count) results=\(resultCount)"
                + " cpu=\(Self.milliseconds(measurement.cpuTime))ms wall=\(Self.milliseconds(measurement.wallTime))ms"
                + " limit=\(Self.milliseconds(limit))ms"
        )
        #expect(measurement.cpuTime <= limit)
    }

    /// 並列に走る他のテストの確保・解放が混ざると上下するため、目標に対して余裕のある差で判定する。
    /// 差し替えにかかる時間（初回の前処理と、同じ候補での再走査）も参考として出す
    @Test("候補 20,000 件を保持したインデックスのヒープ使用量が 30MB 以下")
    func residentMemoryWithinBudget() async throws {
        let items = Self.makeItems(count: Self.residentCandidateCount)
        let ghqItems = Array(items.prefix(Self.queryCandidateCount))
        let rootItems = Array(items.dropFirst(Self.queryCandidateCount))
        let historyItems = Array(items.prefix(Self.historyCount))
        let index = IndexFixtures.makeIndex()
        let timer = ContinuousClock()

        let before = Self.heapBytesInUse()
        let initialBuild = await timer.measure {
            await index.replace(source: .ghq, with: ghqItems)
            await index.replace(source: .root("/Users/takehiro/repos"), with: rootItems)
            await index.replace(source: .history, with: historyItems)
        }
        let after = Self.heapBytesInUse()
        let rescan = await timer.measure {
            await index.replace(source: .root("/Users/takehiro/repos"), with: rootItems)
        }
        let megabytes = Double(after - before) / Self.bytesPerMegabyte

        print(
            "[CandidateIndexBenchmark] resident candidates=\(index.count) heap=\(megabytes)MB"
                + " limit=\(Self.residentMemoryBudgetMegabytes)MB"
                + " initialBuild=\(Self.milliseconds(initialBuild))ms rescanRoots=\(Self.milliseconds(rescan))ms"
        )
        #expect(index.count == Self.residentCandidateCount)
        #expect(megabytes <= Self.residentMemoryBudgetMegabytes)
    }
}
