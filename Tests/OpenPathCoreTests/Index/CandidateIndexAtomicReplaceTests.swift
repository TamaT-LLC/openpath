import Testing

import OpenPathCore

/// TST-001 §2.4「アトミック差し替え: 走査中に query しても旧結果が返り、クラッシュしない」を、
/// 差し替えとクエリを大量に並行させて確かめる。
@Suite("CandidateIndex: アトミック差し替え", .timeLimit(.minutes(1)))
struct CandidateIndexAtomicReplaceTests {
    private typealias F = IndexFixtures

    private static let root = CandidateSourceKind.root("/atomic")
    private static let itemCount = 40
    private static let replaceCount = 200
    private static let queryCount = 200
    private static let concurrentQueryTasks = 4
    /// 両方の候補の集合の全件にマッチするクエリ
    private static let matchingQuery = "item"
    /// 全件を受け取れる上限
    private static let generousLimit = itemCount * 2

    private static func items(_ prefix: String) -> [SourceItem] {
        (0..<itemCount).map { F.directory("/atomic/\(prefix)/item-\($0)") }
    }

    @Test("差し替えと並行したクエリは、差し替え前か後のどちらか一方の候補だけを欠けずに返す")
    func concurrentQueriesSeeWholeSnapshots() async throws {
        let index = F.makeIndex()
        let oldItems = Self.items("old")
        let newItems = Self.items("new")
        let oldPaths = Set(oldItems.map(\.path))
        let newPaths = Set(newItems.map(\.path))
        await index.replace(source: Self.root, with: oldItems)

        let observed = try await withThrowingTaskGroup(of: [Set<String>].self) { group in
            group.addTask {
                for round in 0..<Self.replaceCount {
                    await index.replace(source: Self.root, with: round.isMultiple(of: 2) ? newItems : oldItems)
                }
                return []
            }
            for _ in 0..<Self.concurrentQueryTasks {
                group.addTask {
                    var results: [Set<String>] = []
                    for _ in 0..<Self.queryCount {
                        let ranked = try await index.query(Self.matchingQuery, directoriesOnly: false, limit: Self.generousLimit)
                        results.append(Set(ranked.map(\.candidate.path)))
                    }
                    return results
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }

        #expect(observed.count == Self.concurrentQueryTasks * Self.queryCount)
        #expect(observed.allSatisfy { $0 == oldPaths || $0 == newPaths })
    }
}
