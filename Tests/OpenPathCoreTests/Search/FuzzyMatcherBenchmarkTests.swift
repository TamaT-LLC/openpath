import Darwin
import Testing

import OpenPathCore

/// DSN-002 §8「1 文字入力ごとのマッチ（候補 5,000 件）16ms 以内」の簡易ベンチ。
///
/// 並列に走る他のテストや他プロセスに CPU を奪われた待ち時間まで含めると高負荷時に大きくぶれるため、
/// 判定はマッチ処理を実行したスレッドの CPU 時間で行い、wall-clock は参考としてログに出す。
/// さらに複数回計測した最小値を採る。
@Suite("FuzzyMatcher ベンチマーク", .serialized)
struct FuzzyMatcherBenchmarkTests {
    private struct Measurement {
        let cpuTime: Duration
        let wallTime: Duration
    }

    private static let candidateCount = 5_000
    private static let budget = Duration.milliseconds(16)
    #if DEBUG
    /// デバッグビルドは最適化が効かず、さらに高負荷時は効率コアに回されて数倍遅くなる（ローカル実測 15〜90ms）。
    /// そのため上限を大きく緩め、候補の再正規化や計算量の悪化といった桁違いの退行の検知に留める。
    /// 目標値そのものの判定はリリースビルド（`./scripts/test.sh -c release`）で行う。
    private static let budgetMultiplier = 10
    #else
    private static let budgetMultiplier = 1
    #endif
    private static let measurementCount = 5
    private static let millisecondsPerSecond = 1_000.0
    private static let attosecondsPerMillisecond = 1e15

    private static let queries = ["s", "sd", "sda", "fern", "openpath", "rgtf"]
    private static let words = [
        "openpath", "system", "doc", "agent", "fern", "config", "dotfiles", "notes",
        "api", "server", "client", "tools", "Documents", "Projects", "MyApp", "swift",
        "kit", "web", "infra", "sandbox", "design", "資料", "メモ", "playground",
    ]
    private static let owners = ["TamaT-LLC", "takehiro", "apple", "swiftlang", "junegunn", "ajeetdsouza"]

    private static let matcher = FuzzyMatcher()
    /// 候補の正規化はインデックス構築時に一度だけ行う想定なので、計測の外で済ませて全ケースで共有する
    private static let targets = makeCandidates().map { (name: matcher.prepareTarget($0.name), path: matcher.prepareTarget($0.path)) }

    /// 実際の候補（ghq / roots 配下のリポジトリ）に近い形の name / path を決定的に生成する
    private static func makeCandidates() -> [(name: String, path: String)] {
        (0..<candidateCount).map { index in
            let first = words[index % words.count]
            let second = words[(index / words.count) % words.count]
            let owner = owners[index % owners.count]
            let name = "\(first)-\(second)-\(index)"
            return (name, "/Users/takehiro/repos/github.com/\(owner)/\(name)")
        }
    }

    private static func measure(_ body: () -> Void) -> Measurement {
        let clock = ContinuousClock()
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let wallTime = clock.measure(body)
        let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        return Measurement(cpuTime: .nanoseconds(cpuEnd - cpuStart), wallTime: wallTime)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * millisecondsPerSecond
            + Double(components.attoseconds) / attosecondsPerMillisecond
    }

    @Test("候補 5,000 件 × 1 クエリのマッチが目標時間内に終わる", arguments: queries)
    func matchesCandidatesWithinBudget(query: String) throws {
        var matchCount = 0

        let measurements = (0..<Self.measurementCount).map { _ in
            Self.measure {
                // キー入力ごとにクエリの前処理と全候補のマッチを行う
                let preparedQuery = Self.matcher.prepareQuery(query)
                matchCount = Self.targets.reduce(into: 0) { count, target in
                    if Self.matcher.scoreCandidate(query: preparedQuery, name: target.name, path: target.path) != nil {
                        count += 1
                    }
                }
            }
        }
        let cpuTime = try #require(measurements.map(\.cpuTime).min())
        let wallTime = try #require(measurements.map(\.wallTime).min())
        let limit = Self.budget * Self.budgetMultiplier

        print(
            "[FuzzyMatcherBenchmark] query=\"\(query)\" candidates=\(Self.targets.count) matched=\(matchCount)"
                + " cpu=\(Self.milliseconds(cpuTime))ms wall=\(Self.milliseconds(wallTime))ms"
                + " limit=\(Self.milliseconds(limit))ms"
        )
        #expect(Self.targets.count == Self.candidateCount)
        #expect(matchCount > 0)
        #expect(cpuTime <= limit)
    }
}
