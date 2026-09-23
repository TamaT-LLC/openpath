import Foundation
import Testing

@testable import OpenPathCore

/// 候補が多いときの前置フィルタ（DSN-002 §5「候補数が 10,000 件以上のとき: 先頭 2 文字で前置フィルタしてからマッチ」）。
@Suite("CandidateIndex: 前置フィルタ")
struct CandidateIndexPrefilterTests {
    private typealias F = IndexFixtures

    /// DSN-002 §5 の閾値
    private static let prefilterThreshold = 10_000
    private static let alwaysPrefilter = 0
    private static let neverPrefilter = Int.max

    /// 正規化（大文字小文字・全角・半角カナ・カタカナ・NFD・アクセント）で初めて一致する候補を含める
    private static let normalizationSensitivePaths = [
        "/x/シリョウ",
        "/x/ｼﾘｮｳ_2",
        "/x/" + "データ".decomposedStringWithCanonicalMapping,
        "/x/Doc-Site",
        "/x/ＦＥＲＮ",
        "/x/Café",
        "/x/2026_資料",
        "/x/system-doc-agent",
    ]

    private static let queries = ["しりょう", "シリ", "でーた", "ＤＯＣ", "fern", "cafe", "資料", "sda", "s", "rgtf", "xyz"]

    private static func makeFillerPaths(count: Int) -> [String] {
        let words = ["openpath", "config", "tools", "notes", "web", "infra", "資料", "メモ"]
        return (0..<count).map { index in
            "/Users/me/repos/\(words[index % words.count])-\(index)"
        }
    }

    private static func makeIndex(prefilterThreshold: Int) -> CandidateIndex {
        CandidateIndex(
            fileExistence: RecordingFileExistenceChecker(),
            now: { F.now },
            prefilterThreshold: prefilterThreshold,
            history: { [] }
        )
    }

    @Test("前置フィルタは正規化後の文字で判定するため、使っても使わなくても結果は同じ", arguments: queries)
    func prefilterDoesNotChangeResults(query: String) async throws {
        let items = (Self.normalizationSensitivePaths + Self.makeFillerPaths(count: 200)).map(F.directory)
        let filtered = Self.makeIndex(prefilterThreshold: Self.alwaysPrefilter)
        let unfiltered = Self.makeIndex(prefilterThreshold: Self.neverPrefilter)
        await filtered.replace(source: .root("/"), with: items)
        await unfiltered.replace(source: .root("/"), with: items)

        let filteredResults = try await filtered.query(query, directoriesOnly: false, limit: F.generousLimit)
        let unfilteredResults = try await unfiltered.query(query, directoriesOnly: false, limit: F.generousLimit)

        #expect(filteredResults == unfilteredResults)
    }

    @Test("前置フィルタはクエリの先頭 2 文字（正規化後）を含まない候補をマッチ処理の前に外す")
    func prefilterSkipsCandidatesWithoutLeadingCharacters() {
        let matcher = FuzzyMatcher()
        let paths = ["/x/fern", "/x/abc", "/x/シリョウ", "/x/Fe"]
        let catalog = CandidateCatalog(merging: [.root("/x"): CandidatePreparer(matcher: matcher).prepare(paths.map(F.directory))])

        let ascii = catalog.prefilteredIndices(for: matcher.prepareQuery("ＦＥz")).map { catalog.entries[$0].path }
        let kana = catalog.prefilteredIndices(for: matcher.prepareQuery("しりx")).map { catalog.entries[$0].path }

        // 3 文字目の z は見ないため、z を含まない fern / Fe も残る
        #expect(Set(ascii) == ["/x/fern", "/x/Fe"])
        #expect(kana.contains("/x/シリョウ"))
        #expect(!kana.contains("/x/abc"))
        #expect(!kana.contains("/x/fern"))
    }

    @Test("候補が 10,000 件以上でも、日本語・全角・大文字のクエリで正規化後に一致する候補が見つかる")
    func findsNormalizedMatchesAboveThreshold() async throws {
        let index = F.makeIndex()
        let items = (Self.normalizationSensitivePaths + Self.makeFillerPaths(count: Self.prefilterThreshold)).map(F.directory)
        await index.replace(source: .root("/"), with: items)
        #expect(index.count >= Self.prefilterThreshold)

        let kana = try await index.query("しりょう", directoriesOnly: false, limit: F.generousLimit)
        let fullwidth = try await index.query("ＤＯＣ-Ｓ", directoriesOnly: false, limit: F.generousLimit)
        let voiced = try await index.query("でーた", directoriesOnly: false, limit: F.generousLimit)

        #expect(Set(kana.map(\.candidate.path)) == ["/x/シリョウ", "/x/ｼﾘｮｳ_2"])
        #expect(fullwidth.first?.candidate.path == "/x/Doc-Site")
        #expect(voiced.map(\.candidate.name) == ["データ"])
    }
}
