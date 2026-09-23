import Testing

import OpenPathCore

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    private let matcher = FuzzyMatcher()

    // MARK: - TST-001 §2.1

    @Test("先頭一致が最上位: fern > fernet-config > my-fern")
    func prefixMatchRanksHighest() throws {
        let fern = try #require(matcher.score(query: "fern", in: "fern"))
        let fernetConfig = try #require(matcher.score(query: "fern", in: "fernet-config"))
        let myFern = try #require(matcher.score(query: "fern", in: "my-fern"))

        #expect(fern.score > fernetConfig.score)
        #expect(fernetConfig.score > myFern.score)
    }

    @Test("区切り直後ボーナス: sda では system-doc-agent が sdasd より上位")
    func separatorBonusBeatsPlainPrefix() throws {
        let systemDocAgent = try #require(matcher.score(query: "sda", in: "system-doc-agent"))
        let sdasd = try #require(matcher.score(query: "sda", in: "sdasd"))

        #expect(systemDocAgent.score > sdasd.score)
        #expect(systemDocAgent.positions == [0, 7, 11])
    }

    @Test("非マッチ: xyz は fern にマッチしない")
    func nonMatchReturnsNil() {
        #expect(matcher.score(query: "xyz", in: "fern") == nil)
    }

    @Test("positions: fn / fern は [0, 3]")
    func positionsPointToMatchedCharacters() {
        #expect(matcher.score(query: "fn", in: "fern")?.positions == [0, 3])
    }

    // MARK: - マッチ可否

    @Test("クエリの文字順がテキストと異なればマッチしない")
    func outOfOrderQueryDoesNotMatch() {
        #expect(matcher.score(query: "ba", in: "ab") == nil)
    }

    @Test("クエリがテキストより長ければマッチしない")
    func longerQueryDoesNotMatch() {
        #expect(matcher.score(query: "ferns", in: "fern") == nil)
    }

    @Test("空テキストには非空クエリがマッチしない")
    func emptyTextDoesNotMatch() {
        #expect(matcher.score(query: "a", in: "") == nil)
    }

    @Test("空クエリは全テキストにマッチし、positions は空")
    func emptyQueryMatchesEverything() throws {
        let match = try #require(matcher.score(query: "", in: "fern"))

        #expect(match.positions.isEmpty)
        #expect(match.score >= 1)
    }

    @Test("大文字小文字を区別しない", arguments: [("FERN", "fern"), ("fern", "Fern"), ("FeRn", "fErN")])
    func caseInsensitive(query: String, text: String) {
        #expect(matcher.score(query: query, in: text)?.positions == [0, 1, 2, 3])
    }

    // MARK: - positions

    @Test("positions は Unicode スカラーではなく Character（書記素クラスタ）単位のオフセット")
    func positionsAreCharacterOffsets() {
        // 結合文字（e + U+0301）と ZWJ 絵文字はそれぞれ 1 Character として数える
        #expect(matcher.score(query: "b", in: "e\u{301}-b")?.positions == [2])
        #expect(matcher.score(query: "b", in: "👨‍👩‍👧/b")?.positions == [2])
        #expect(matcher.score(query: "料メ", in: "資料/メモ")?.positions == [1, 3])
    }

    @Test("同じ文字が複数回出る場合、ボーナスの高い位置を選ぶ", arguments: [
        ("fern", "f-fern", [2, 3, 4, 5]),
        ("b", "abc-b", [4]),
        ("sda", "system-doc-agent", [0, 7, 11]),
    ])
    func prefersHigherBonusOccurrence(query: String, text: String, expected: [Int]) {
        #expect(matcher.score(query: query, in: text)?.positions == expected)
    }

    // MARK: - スコア規則（DSN-002 §5）

    /// 期待値は実装の定数を参照せず、DSN-002 §5 の仕様値から独立に組み立てる。
    private enum Spec {
        static let head = 16
        static let separator = 12
        static let camelCase = 8
        static let consecutive = 6
        static let gapPerCharacter = 3
        static let gapPerCharacterBeforeBoundary = 1
        static let exactMatch = 16
        static let minimumScore = 1
    }

    struct ScoringCase: Sendable, CustomTestStringConvertible {
        let rule: String
        let query: String
        let text: String
        let expectedScore: Int

        var testDescription: String { "\(rule): \(query) / \(text) → \(expectedScore)" }
    }

    static let scoringCases: [ScoringCase] = [
        ScoringCase(rule: "先頭一致", query: "a", text: "abc", expectedScore: Spec.head),
        ScoringCase(rule: "/ 直後", query: "b", text: "a/b", expectedScore: Spec.separator),
        ScoringCase(rule: "- 直後", query: "b", text: "a-b", expectedScore: Spec.separator),
        ScoringCase(rule: "_ 直後", query: "b", text: "a_b", expectedScore: Spec.separator),
        ScoringCase(rule: ". 直後", query: "b", text: "a.b", expectedScore: Spec.separator),
        ScoringCase(rule: "CamelCase 境界", query: "b", text: "aBc", expectedScore: Spec.camelCase),
        ScoringCase(rule: "先頭側の未マッチ文字は罰しない", query: "b", text: "xxxx-b", expectedScore: Spec.separator),
        ScoringCase(rule: "連続一致", query: "ab", text: "abc", expectedScore: Spec.head + Spec.consecutive),
        ScoringCase(rule: "ギャップ 1 文字", query: "ac", text: "abc", expectedScore: Spec.head - Spec.gapPerCharacter),
        ScoringCase(rule: "ギャップ 2 文字", query: "ad", text: "abcd", expectedScore: Spec.head - 2 * Spec.gapPerCharacter),
        ScoringCase(
            rule: "境界に着地するギャップは軽い",
            query: "ac",
            text: "ab-c",
            expectedScore: Spec.head + Spec.separator - 2 * Spec.gapPerCharacterBeforeBoundary
        ),
        ScoringCase(
            rule: "完全一致",
            query: "ab",
            text: "ab",
            expectedScore: Spec.head + Spec.consecutive + Spec.exactMatch
        ),
        ScoringCase(rule: "ボーナスなしは最低スコア", query: "b", text: "abc", expectedScore: Spec.minimumScore),
        ScoringCase(rule: "負のスコアは最低スコアに丸める", query: "bz", text: "abcdefghz", expectedScore: Spec.minimumScore),
    ]

    @Test("スコア規則", arguments: scoringCases)
    func scoringRule(_ scoringCase: ScoringCase) {
        #expect(matcher.score(query: scoringCase.query, in: scoringCase.text)?.score == scoringCase.expectedScore)
    }

    @Test("CamelCase 境界は小文字化の前の元の文字列で判定する")
    func camelCaseIsDetectedOnOriginalText() {
        let match = matcher.score(query: "fb", in: "fooBar")

        #expect(match?.positions == [0, 3])
        #expect(match?.score == Spec.head + Spec.camelCase - 2 * Spec.gapPerCharacterBeforeBoundary)
    }

    // MARK: - 前処理済み API

    @Test("前処理済みのクエリ・対象でも String 版と同じ結果になる")
    func preparedApiMatchesStringApi() {
        let texts = ["fern", "fernet-config", "my-fern", "system-doc-agent", "sdasd", "fooBar"]
        let query = matcher.prepareQuery("fern")

        for text in texts {
            #expect(matcher.score(query: query, in: matcher.prepareTarget(text)) == matcher.score(query: "fern", in: text))
        }
    }
}
