import Foundation
import Testing

import OpenPathCore

/// DSN-002 §8「roots 走査（2 階層、5,000 件）2 秒以内」の簡易ベンチ。
///
/// 走査はファイルシステムの読み取りが主で、利用者が待つのは経過時間なので wall-clock で判定する。
/// 並列に走る他のテストに I/O や CPU を奪われた分のぶれを抑えるため、複数回計測した最小値を採る。
@Suite("RootDirectoryScanner ベンチマーク", .serialized)
struct RootDirectoryScannerBenchmarkTests {
    /// 1 階層目のディレクトリ数。それぞれの下に `childrenPerParent` 個を作り、ルート配下を計 5,000 件にする
    private static let parentCount = 50
    private static let childrenPerParent = 99
    private static let entryCount = parentCount * (1 + childrenPerParent)
    /// ルート配下の 5,000 件にルート自身を加えた件数
    private static let expectedItemCount = entryCount + 1
    private static let scanDepth = 2

    private static let budget = Duration.seconds(2)
    #if DEBUG
    /// デバッグビルドは最適化が効かず、CI の共有ランナーは I/O も遅いため上限を緩め、桁違いの退行の検知に留める。
    /// 目標値そのものの判定はリリースビルド（`./scripts/test.sh -c release`）で行う。
    private static let budgetMultiplier = 3
    #else
    private static let budgetMultiplier = 1
    #endif
    private static let measurementCount = 3
    private static let millisecondsPerSecond = 1_000.0
    private static let attosecondsPerMillisecond = 1e15

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * millisecondsPerSecond
            + Double(components.attoseconds) / attosecondsPerMillisecond
    }

    @Test("2 階層・5,000 件のルートの走査が目標時間内に終わる")
    func scansFiveThousandEntriesWithinBudget() throws {
        let tree = try FileTreeFixture()
        for parent in 0..<Self.parentCount {
            for child in 0..<Self.childrenPerParent {
                try tree.makeDirectories("project-\(parent)/module-\(child)")
            }
        }
        let scanner = RootDirectoryScanner(options: RootScanOptions(depth: Self.scanDepth))
        let timer = ContinuousClock()
        var itemCount = 0

        let durations = try (0..<Self.measurementCount).map { _ in
            try timer.measure {
                itemCount = try scanner.scan(root: tree.root).items.count
            }
        }
        let fastest = try #require(durations.min())
        let limit = Self.budget * Self.budgetMultiplier

        print(
            "[RootDirectoryScannerBenchmark] entries=\(Self.entryCount) items=\(itemCount)"
                + " wall=\(durations.map(Self.milliseconds))ms fastest=\(Self.milliseconds(fastest))ms"
                + " limit=\(Self.milliseconds(limit))ms"
        )
        #expect(itemCount == Self.expectedItemCount)
        #expect(fastest <= limit)
    }
}
