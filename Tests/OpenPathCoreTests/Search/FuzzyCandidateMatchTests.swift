import Testing

import OpenPathCore

@Suite("FuzzyMatcher.scoreCandidate（name / path の両方にマッチ）")
struct FuzzyCandidateMatchTests {
    /// DSN-002 §5: name マッチには +20% のボーナス
    private static let nameBonusPercent = 20
    private static let percentBase = 100

    private let matcher = FuzzyMatcher()

    @Test("name のスコアには +20% のボーナスが付き、高い方として name が採用される")
    func nameMatchGetsBonus() throws {
        let nameMatch = try #require(matcher.score(query: "fern", in: "fern"))

        let match = try #require(matcher.scoreCandidate(query: "fern", name: "fern", path: "/Users/me/repos/fern"))

        #expect(match.field == .name)
        #expect(match.positions == [0, 1, 2, 3])
        #expect(match.score == nameMatch.score + nameMatch.score * Self.nameBonusPercent / Self.percentBase)
    }

    @Test("name にマッチしなければ path のマッチを採用し、positions は path 上のオフセット")
    func fallsBackToPath() throws {
        let path = "/Users/me/repos/fern"
        let pathMatch = try #require(matcher.score(query: "rf", in: path))

        let match = try #require(matcher.scoreCandidate(query: "rf", name: "fern", path: path))

        #expect(match.field == .path)
        #expect(match.positions == [10, 16])
        #expect(match.score == pathMatch.score)
    }

    @Test("両方にマッチしても path の方が高ければ path を採用する")
    func prefersHigherPathScore() throws {
        let match = try #require(matcher.scoreCandidate(query: "ab", name: "xaxb", path: "/ab/xaxb"))

        #expect(match.field == .path)
        #expect(match.positions == [1, 2])
    }

    @Test("同点なら name を採用する")
    func prefersNameOnTie() throws {
        let match = try #require(matcher.scoreCandidate(query: "b", name: "ab", path: "ab"))

        #expect(match.field == .name)
    }

    @Test("どちらにもマッチしなければ nil")
    func noMatch() {
        #expect(matcher.scoreCandidate(query: "xyz", name: "fern", path: "/a/fern") == nil)
    }

    @Test("前処理済み API でも String 版と同じ結果になる")
    func preparedApiMatchesStringApi() {
        let query = matcher.prepareQuery("rf")
        let name = matcher.prepareTarget("fern")
        let path = matcher.prepareTarget("/Users/me/repos/fern")

        #expect(
            matcher.scoreCandidate(query: query, name: name, path: path)
                == matcher.scoreCandidate(query: "rf", name: "fern", path: "/Users/me/repos/fern")
        )
    }
}
