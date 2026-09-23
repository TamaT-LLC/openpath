import Foundation
import Testing

import OpenPathCore

/// クエリの順位付けと絞り込み（DSN-002 §4〜§5、TST-001 §2.4「ディレクトリのみ要求」「空クエリ」）。
@Suite("CandidateIndex: クエリ")
struct CandidateIndexQueryTests {
    private typealias F = IndexFixtures

    private let matcher = FuzzyMatcher()

    // MARK: - 順位付け

    @Test("総合スコアは fuzzyScore × (1 + log1p(frecency)) で、その降順に並ぶ")
    func ranksByFuzzyScoreTimesFrecency() async throws {
        let exact = "/repos/fern"
        let frequent = "/repos/fernet-config"
        let history = [HistoryEntry(path: frequent, count: 10, lastUsed: F.ago(F.oneHour / 2))]
        let index = F.makeIndex(history: history)
        await index.replace(source: .ghq, with: [F.directory(exact), F.directory(frequent)])

        let results = try await index.query("fern", directoriesOnly: false, limit: F.generousLimit)

        let frecency = history[0].frecency(now: F.now)
        let exactScore = try #require(matcher.scoreCandidate(query: "fern", name: "fern", path: exact)).score
        let frequentScore = try #require(matcher.scoreCandidate(query: "fern", name: "fernet-config", path: frequent)).score
        // 名前が完全一致する fern より、よく使う fernet-config が上に来る
        #expect(results.map(\.candidate.path) == [frequent, exact])
        #expect(results.map(\.score) == [Double(frequentScore) * (1 + log1p(frecency)), Double(exactScore)])
        #expect(results.map(\.candidate.frecency) == [frecency, 0])
    }

    @Test("履歴にない候補同士はファジーマッチのスコア順になる")
    func ranksByFuzzyScoreWithoutHistory() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/repos/my-fern"), F.directory("/repos/fernet-config"), F.directory("/repos/fern")])

        let results = try await index.query("fern", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.map(\.candidate.name) == ["fern", "fernet-config", "my-fern"])
    }

    @Test("総合スコアが同じ候補はパスの昇順に並べ、順序を決定的にする")
    func breaksTiesByPath() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/b/app"), F.directory("/c/app"), F.directory("/a/app")])

        let results = try await index.query("app", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.map(\.candidate.path) == ["/a/app", "/b/app", "/c/app"])
    }

    @Test("マッチ結果（name / path と一致位置）を候補と一緒に返す")
    func returnsMatchDetails() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/Users/me/repos/fern")])

        let byName = try #require(try await index.query("fn", directoriesOnly: false, limit: F.generousLimit).first)
        let byPath = try #require(try await index.query("rf", directoriesOnly: false, limit: F.generousLimit).first)

        #expect(byName.match == matcher.scoreCandidate(query: "fn", name: "fern", path: "/Users/me/repos/fern"))
        #expect(byName.match?.field == .name)
        #expect(byPath.match?.field == .path)
    }

    @Test("どの候補にもマッチしなければ空")
    func returnsEmptyWhenNothingMatches() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/repos/fern")])

        #expect(try await index.query("xyz", directoriesOnly: false, limit: F.generousLimit).isEmpty)
    }

    // MARK: - ディレクトリのみ（FR-SOURCE-05）

    @Test("directoriesOnly: true ではファイルを返さない")
    func directoriesOnlyExcludesFiles() async throws {
        let index = F.makeIndex()
        await index.replace(source: .root("/repos"), with: [F.directory("/repos/doc-site"), F.file("/repos/doc.txt"), F.file("/repos/Docs.app")])

        let directories = try await index.query("doc", directoriesOnly: true, limit: F.generousLimit)
        let all = try await index.query("doc", directoriesOnly: false, limit: F.generousLimit)

        #expect(directories.map(\.candidate.path) == ["/repos/doc-site"])
        #expect(directories.allSatisfy { $0.candidate.isDirectory })
        #expect(Set(all.map(\.candidate.path)) == ["/repos/doc-site", "/repos/doc.txt", "/repos/Docs.app"])
    }

    // MARK: - 空クエリ（UX-001 §2）

    @Test("空クエリは frecency 降順の上位 8 件を返す")
    func emptyQueryReturnsTopEightByFrecency() async throws {
        let paths = (1...10).map { "/repos/project-\($0)" }
        // count が大きいほど frecency が高い
        let history = paths.enumerated().map { offset, path in
            HistoryEntry(path: path, count: offset + 1, lastUsed: F.ago(F.oneDay * 2))
        }
        let index = F.makeIndex(history: history)
        await index.replace(source: .history, with: paths.map(F.directory))

        let results = try await index.query("", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.count == F.emptyQueryLimit)
        #expect(results.map(\.candidate.path) == Array(paths.reversed().prefix(F.emptyQueryLimit)))
        #expect(results.map(\.score) == results.map(\.candidate.frecency))
        #expect(results.allSatisfy { $0.match == nil })
    }

    @Test("空クエリで履歴が 8 件に満たない場合は、履歴のない候補をパスの昇順で補う")
    func emptyQueryFillsWithCandidatesWithoutHistory() async throws {
        let history = [
            HistoryEntry(path: "/repos/used-less", count: 1, lastUsed: F.ago(F.oneDay * 2)),
            HistoryEntry(path: "/repos/used-more", count: 5, lastUsed: F.ago(F.oneDay * 2)),
        ]
        let unused = (1...9).map { "/repos/unused-\($0)" }
        let index = F.makeIndex(history: history)
        await index.replace(source: .history, with: history.map { F.directory($0.path) })
        await index.replace(source: .root("/repos"), with: unused.map(F.directory))

        let results = try await index.query("", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.map(\.candidate.path) == ["/repos/used-more", "/repos/used-less"] + unused.sorted().prefix(6))
    }

    @Test("空クエリでも directoriesOnly と limit が効く")
    func emptyQueryHonorsDirectoriesOnlyAndLimit() async throws {
        let history = [
            HistoryEntry(path: "/repos/notes.md", count: 9, lastUsed: F.ago(F.oneHour / 2)),
            HistoryEntry(path: "/repos/app", count: 1, lastUsed: F.ago(F.oneDay * 2)),
        ]
        let index = F.makeIndex(history: history)
        await index.replace(source: .history, with: [F.file("/repos/notes.md"), F.directory("/repos/app")])
        await index.replace(source: .root("/repos"), with: [F.directory("/repos/lib"), F.directory("/repos/web")])

        let directories = try await index.query("", directoriesOnly: true, limit: 2)

        #expect(directories.map(\.candidate.path) == ["/repos/app", "/repos/lib"])
    }

    // MARK: - 件数

    @Test("limit を超えて返さない。0 以下なら空")
    func honorsLimit() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: (1...5).map { F.directory("/repos/app-\($0)") })

        #expect(try await index.query("app", directoriesOnly: false, limit: 2).count == 2)
        #expect(try await index.query("app", directoriesOnly: false, limit: 0).isEmpty)
        #expect(try await index.query("", directoriesOnly: false, limit: -1).isEmpty)
    }

    // MARK: - 履歴（frecency / lastUsed）

    @Test("frecency と最終使用日時は履歴から正規化後のパスで引き、履歴にない候補は 0 と nil")
    func looksUpHistoryByNormalizedPath() async throws {
        let lastUsed = F.ago(F.oneDay * 3)
        let history = [HistoryEntry(path: "/repos/app/", count: 2, lastUsed: lastUsed)]
        let index = F.makeIndex(history: history)
        await index.replace(source: .ghq, with: [F.directory("/repos/app"), F.directory("/repos/api")])

        let results = try await index.query("ap", directoriesOnly: false, limit: F.generousLimit)

        let byPath = Dictionary(uniqueKeysWithValues: results.map { ($0.candidate.path, $0.candidate) })
        #expect(byPath["/repos/app"]?.frecency == history[0].frecency(now: F.now))
        #expect(byPath["/repos/app"]?.lastUsed == lastUsed)
        #expect(byPath["/repos/api"]?.frecency == 0)
        #expect(byPath["/repos/api"]?.lastUsed == nil)
    }

    @Test("正規化すると同じパスになる履歴が複数あれば、frecency は合算し最終使用日時は新しい方を採る")
    func combinesHistoryEntriesWithSameNormalizedPath() async throws {
        let older = HistoryEntry(path: "/repos/app", count: 3, lastUsed: F.ago(F.oneDay * 10))
        let newer = HistoryEntry(path: "/repos//app/", count: 1, lastUsed: F.ago(F.oneHour / 2))
        let index = F.makeIndex(history: [older, newer])
        await index.replace(source: .ghq, with: [F.directory("/repos/app")])

        let candidate = try #require(try await index.query("", directoriesOnly: false, limit: F.generousLimit).first?.candidate)

        #expect(candidate.frecency == older.frecency(now: F.now) + newer.frecency(now: F.now))
        #expect(candidate.lastUsed == newer.lastUsed)
    }

    @Test("履歴は query のたびに引き直し、差し替え後の記録も順位に反映する")
    @MainActor
    func readsHistoryOnEveryQuery() async throws {
        let persistence = HistoryPersistenceSpy()
        let store = HistoryStore(persistence: persistence, now: { F.now }, fileExistence: StubFileExistenceChecker())
        let index = CandidateIndex(historyStore: store, fileExistence: RecordingFileExistenceChecker(), now: { F.now })
        await index.replace(source: .ghq, with: [F.directory("/repos/api"), F.directory("/repos/app")])

        let before = try await index.query("", directoriesOnly: false, limit: F.generousLimit)
        store.record(path: "/repos/app")
        let after = try await index.query("", directoriesOnly: false, limit: F.generousLimit)

        #expect(before.map(\.candidate.path) == ["/repos/api", "/repos/app"])
        #expect(after.map(\.candidate.path) == ["/repos/app", "/repos/api"])
        #expect(after.first?.candidate.lastUsed == F.now)
    }

    // MARK: - 存在確認（FR-HISTORY-03）

    @Test("存在しない候補は除外して繰り上げ、存在確認は返す件数に達するまでしか行わない")
    func skipsMissingCandidates() async throws {
        let paths = ["/repos/app-1", "/repos/app-2", "/repos/app-3", "/repos/app-4"]
        let existence = RecordingFileExistenceChecker(missingPaths: ["/repos/app-2"])
        let index = F.makeIndex(existence: existence)
        await index.replace(source: .ghq, with: paths.map(F.directory))

        let results = try await index.query("app", directoriesOnly: false, limit: 2)

        #expect(results.map(\.candidate.path) == ["/repos/app-1", "/repos/app-3"])
        #expect(existence.checkedPaths == ["/repos/app-1", "/repos/app-2", "/repos/app-3"])
    }

    @Test("空クエリでも存在しない候補は除外する")
    func skipsMissingCandidatesForEmptyQuery() async throws {
        let history = [
            HistoryEntry(path: "/repos/gone", count: 9, lastUsed: F.ago(F.oneHour / 2)),
            HistoryEntry(path: "/repos/app", count: 1, lastUsed: F.ago(F.oneDay * 2)),
        ]
        let existence = RecordingFileExistenceChecker(missingPaths: ["/repos/gone"])
        let index = F.makeIndex(history: history, existence: existence)
        await index.replace(source: .history, with: history.map { F.directory($0.path) })

        let results = try await index.query("", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.map(\.candidate.path) == ["/repos/app"])
    }

    // MARK: - 日本語（FR-PALETTE-06）

    @Test(
        "日本語のクエリは正規化（かな・NFC/NFD・幅・大文字小文字の同一視）してから候補にマッチする",
        arguments: [
            ("しりょう", "/x/シリョウ"),
            ("でーた", "/x/" + "データ".decomposedStringWithCanonicalMapping),
            ("ＤＯＣ", "/x/Doc"),
            ("資料", "/x/2026_資料"),
        ]
    )
    func matchesJapaneseQueries(query: String, path: String) async throws {
        let index = F.makeIndex()
        await index.replace(source: .root("/x"), with: [F.directory(path), F.directory("/x/zzz")])

        let results = try await index.query(query, directoriesOnly: false, limit: F.generousLimit)

        #expect(results.map(\.candidate.path) == [path])
        #expect(results.first?.match?.field == .name)
    }

    // MARK: - 並行性

    @Test("クエリのマッチと存在確認はメインスレッドの外で行う")
    @MainActor
    func runsOffTheMainThread() async throws {
        let existence = RecordingFileExistenceChecker()
        let index = F.makeIndex(existence: existence)
        await index.replace(source: .ghq, with: [F.directory("/repos/app")])

        let results = try await index.query("app", directoriesOnly: false, limit: F.generousLimit)

        #expect(results.count == 1)
        #expect(existence.checkedPaths == ["/repos/app"])
        #expect(!existence.wasCheckedOnMainThread)
    }

    @Test("キャンセルされたクエリは CancellationError を投げる")
    func throwsWhenCancelled() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/repos/app")])

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.query("app", directoriesOnly: false, limit: F.generousLimit)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
