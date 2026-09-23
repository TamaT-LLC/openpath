import Foundation
import Testing

import OpenPathCore

/// 候補とマッチ結果からパレットの行への変換（FR-PALETTE-03）。
@Suite("PaletteRow: 候補からの変換")
struct PaletteRowCandidateTests {
    private typealias F = IndexFixtures

    private static let candidate = Candidate(
        path: "/Users/me/repos/fern",
        name: "fern",
        isDirectory: true,
        source: .history,
        frecency: 4,
        lastUsed: F.ago(F.oneHour)
    )

    @Test("name にマッチした場合は一致位置を nameHighlights にする")
    func nameMatchHighlightsName() {
        let match = FuzzyCandidateMatch(score: 10, field: .name, positions: [0, 3])

        let row = PaletteRow(candidate: Self.candidate, match: match)

        #expect(row == PaletteRow(
            name: "fern",
            path: "/Users/me/repos/fern",
            lastUsed: F.ago(F.oneHour),
            nameHighlights: [0, 3],
            pathHighlights: []
        ))
    }

    @Test("path にマッチした場合は一致位置を pathHighlights にする")
    func pathMatchHighlightsPath() {
        let match = FuzzyCandidateMatch(score: 10, field: .path, positions: [10, 16])

        let row = PaletteRow(candidate: Self.candidate, match: match)

        #expect(row.nameHighlights.isEmpty)
        #expect(row.pathHighlights == [10, 16])
    }

    @Test("マッチ結果が無い（空クエリ）場合はハイライトしない。履歴にない候補は最終使用日時が空")
    func noMatchHasNoHighlights() {
        let unused = Candidate(path: "/repos/app", name: "app", isDirectory: true, source: .ghq, frecency: 0, lastUsed: nil)

        let row = PaletteRow(candidate: unused, match: nil)

        #expect(row == PaletteRow(name: "app", path: "/repos/app", lastUsed: nil))
    }

    @Test("クエリの結果から、マッチした文字をハイライトした行を作れる")
    func rankedCandidateProducesRow() async throws {
        let index = F.makeIndex()
        await index.replace(source: .ghq, with: [F.directory("/Users/me/repos/fern")])

        let byName = try #require(try await index.query("fn", directoriesOnly: false, limit: F.generousLimit).first)
        let byPath = try #require(try await index.query("rf", directoriesOnly: false, limit: F.generousLimit).first)

        #expect(byName.paletteRow.nameHighlights == [0, 3])
        #expect(byName.paletteRow.pathHighlights.isEmpty)
        // "/Users/me/repos/" の r（10）と fern の f（16）
        #expect(byPath.paletteRow.pathHighlights == [10, 16])
        #expect(byPath.paletteRow.nameHighlights.isEmpty)
    }
}
