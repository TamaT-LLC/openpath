import Foundation
import Testing

import OpenPathCore

/// 候補ソースの統合（DSN-002 §3、TST-001 §2.4「ソース統合」）。
@Suite("CandidateIndex: ソースの統合")
struct CandidateIndexMergeTests {
    private typealias F = IndexFixtures

    /// 空クエリで全件を見るための上限（空クエリの上限 8 件に収まる件数で使う）
    private static let allLimit = F.emptyQueryLimit

    private static func allCandidates(in index: CandidateIndex, directoriesOnly: Bool = false) async throws -> [Candidate] {
        try await index.query("", directoriesOnly: directoriesOnly, limit: allLimit).map(\.candidate)
    }

    @Test("同一パスが history と ghq にある場合は 1 件に統合し、source は .history になる")
    func mergesHistoryAndGhq() async throws {
        let index = F.makeIndex()
        let path = "/Users/me/repos/github.com/TamaT-LLC/openpath"

        await index.replace(source: .ghq, with: [F.directory(path)])
        await index.replace(source: .history, with: [F.directory(path)])

        let candidates = try await Self.allCandidates(in: index)
        #expect(index.count == 1)
        #expect(candidates.map(\.path) == [path])
        #expect(candidates.map(\.source) == [.history])
    }

    @Test("統合の優先度は差し替えの順序に依らない: history > ghq > roots")
    func mergePriorityIsIndependentOfOrder() async throws {
        let shared = "/Users/me/repos/github.com/TamaT-LLC/openpath"
        let ghqAndRoot = "/Users/me/repos/github.com/TamaT-LLC/fern"
        let index = F.makeIndex()

        await index.replace(source: .history, with: [F.directory(shared)])
        await index.replace(source: .root("/Users/me/repos"), with: [F.directory(shared), F.directory(ghqAndRoot)])
        await index.replace(source: .ghq, with: [F.directory(shared), F.directory(ghqAndRoot)])

        let sources = Dictionary(uniqueKeysWithValues: try await Self.allCandidates(in: index).map { ($0.path, $0.source) })
        #expect(sources == [shared: .history, ghqAndRoot: .ghq])
    }

    @Test("入れ子のルートで同じパスが出た場合は 1 件にし、source はルートの文字列の昇順で先のルート")
    func mergesNestedRoots() async throws {
        let index = F.makeIndex()
        let path = "/Users/me/repos/app"

        await index.replace(source: .root("/Users/me/repos"), with: [F.directory(path)])
        await index.replace(source: .root("/Users/me"), with: [F.directory(path)])

        let candidates = try await Self.allCandidates(in: index)
        #expect(candidates.map(\.source) == [.root("/Users/me")])
    }

    @Test(
        "末尾の / や // . .. を字句的に正規化してから統合し、候補のパスも正規化後の表記にする",
        arguments: ["/Users/me/repos/app/", "/Users/me//repos/app", "/Users/me/./repos/app", "/Users/me/tmp/../repos/app"]
    )
    func normalizesPathsBeforeMerging(spelling: String) async throws {
        let index = F.makeIndex()

        await index.replace(source: .ghq, with: [F.directory("/Users/me/repos/app")])
        await index.replace(source: .history, with: [F.directory(spelling)])

        let candidates = try await Self.allCandidates(in: index)
        #expect(candidates.map(\.path) == ["/Users/me/repos/app"])
        #expect(candidates.map(\.source) == [.history])
    }

    @Test("NFC と NFD で表記が異なる同じパスは 1 件に統合する")
    func mergesCanonicallyEquivalentPaths() async throws {
        let index = F.makeIndex()
        let composed = "/Users/me/Documents/データ"

        await index.replace(source: .root("/Users/me/Documents"), with: [F.directory(composed.decomposedStringWithCanonicalMapping)])
        await index.replace(source: .history, with: [F.directory(composed)])

        #expect(index.count == 1)
        #expect(try await Self.allCandidates(in: index).map(\.source) == [.history])
    }

    @Test("ソースによって isDirectory が食い違う場合はファイルとして扱い、ディレクトリのみの要求には出さない")
    func conflictingDirectoryFlagIsTreatedAsFile() async throws {
        let index = F.makeIndex()
        let path = "/Users/me/repos/changed"

        await index.replace(source: .ghq, with: [F.directory(path)])
        await index.replace(source: .root("/Users/me/repos"), with: [F.file(path)])

        #expect(try await Self.allCandidates(in: index).map(\.isDirectory) == [false])
        #expect(try await Self.allCandidates(in: index, directoriesOnly: true).isEmpty)
    }

    @Test("同じソースの中で重複したパスも 1 件にする")
    func mergesDuplicatesWithinSource() async throws {
        let index = F.makeIndex()

        await index.replace(source: .history, with: [F.directory("/a/b"), F.directory("/a/b/")])

        #expect(index.count == 1)
    }

    @Test("replace は同じソースの前回の候補だけを置き換え、他のソースの候補は残す")
    func replaceSwapsOnlyTheGivenSource() async throws {
        let index = F.makeIndex()

        await index.replace(source: .ghq, with: [F.directory("/repos/old"), F.directory("/repos/shared")])
        await index.replace(source: .root("/Users/me"), with: [F.directory("/Users/me/docs"), F.directory("/repos/shared")])
        await index.replace(source: .ghq, with: [F.directory("/repos/new")])

        let candidates = try await Self.allCandidates(in: index)
        #expect(candidates.map(\.path) == ["/Users/me/docs", "/repos/new", "/repos/shared"])
        #expect(candidates.last?.source == .root("/Users/me"))
    }

    @Test("異なるソースの差し替えが並行しても、すべての差し替えを反映した候補が残る")
    func concurrentReplacesOfDifferentSourcesAreAllApplied() async {
        let index = F.makeIndex()
        let rootCount = 16
        let itemsPerRoot = 20

        await withTaskGroup(of: Void.self) { group in
            for root in 0..<rootCount {
                group.addTask {
                    let rootPath = "/roots/\(root)"
                    await index.replace(source: .root(rootPath), with: (0..<itemsPerRoot).map { F.directory("\(rootPath)/item-\($0)") })
                }
            }
        }

        #expect(index.count == rootCount * itemsPerRoot)
    }

    @Test("空の候補で replace するとそのソースの候補が消える")
    func replaceWithEmptyRemovesSource() async throws {
        let index = F.makeIndex()

        await index.replace(source: .ghq, with: [F.directory("/repos/app")])
        await index.replace(source: .ghq, with: [])

        #expect(index.count == 0)
        #expect(try await Self.allCandidates(in: index).isEmpty)
    }

    @Test("絶対パスでない候補は移動先にできないため含めない", arguments: ["repos/app", "~/repos/app", ""])
    func skipsNonAbsolutePaths(path: String) async throws {
        let index = F.makeIndex()

        await index.replace(source: .history, with: [F.directory(path), F.directory("/repos/app")])

        #expect(try await Self.allCandidates(in: index).map(\.path) == ["/repos/app"])
    }

    @Test("表示名はパスの末尾要素。ルートは / のまま")
    func namesAreLastPathComponents() async throws {
        let index = F.makeIndex()

        await index.replace(source: .root("/"), with: [F.directory("/"), F.directory("/Users/me/資料"), F.file("/Users/me/memo.txt")])

        let names = try await Self.allCandidates(in: index).map(\.name)
        #expect(names == ["/", "memo.txt", "資料"])
    }
}
