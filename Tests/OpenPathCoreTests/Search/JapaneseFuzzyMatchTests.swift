import Foundation
import Testing

import OpenPathCore

@Suite("FuzzyMatcher（日本語・Unicode の同一視）")
struct JapaneseFuzzyMatchTests {
    private let matcher = FuzzyMatcher()

    // MARK: - TST-001 §2.1

    @Test("日本語 NFC/NFD 同一視: NFD で保存された 資料 に 資料 がマッチする")
    func nfdStoredShiryouMatches() {
        let stored = "資料".decomposedStringWithCanonicalMapping

        #expect(matcher.score(query: "資料", in: stored)?.positions == [0, 1])
    }

    @Test("日本語 NFC/NFD 同一視: 濁点・半濁点が分解された候補にも NFC のクエリがマッチする（逆も同様）", arguments: [
        "データ", "ガイド", "パスポート", "ビジネス資料",
    ])
    func nfdStoredVoicedKanaMatches(text: String) {
        let stored = text.decomposedStringWithCanonicalMapping
        // 前提: 濁点・半濁点が結合文字に分解されている
        #expect(stored.unicodeScalars.count > text.unicodeScalars.count)
        let expected = Array(0..<text.count)

        #expect(matcher.score(query: text, in: stored)?.positions == expected)
        #expect(matcher.score(query: stored, in: text)?.positions == expected)
    }

    @Test("かな同一視: しりょう が シリョウ にマッチする（逆も同様）")
    func hiraganaMatchesKatakana() {
        #expect(matcher.score(query: "しりょう", in: "シリョウ")?.positions == [0, 1, 2, 3])
        #expect(matcher.score(query: "シリョウ", in: "しりょう")?.positions == [0, 1, 2, 3])
    }

    @Test("幅同一視: ａｂｃ が abc にマッチする（逆も同様）")
    func fullwidthMatchesHalfwidth() {
        #expect(matcher.score(query: "ａｂｃ", in: "abc")?.positions == [0, 1, 2])
        #expect(matcher.score(query: "abc", in: "ａｂｃ")?.positions == [0, 1, 2])
    }

    @Test("同一視した一致のスコアは、同じ文字どうしの一致と等しい", arguments: [
        ("しりょう", "シリョウ", "しりょう"),
        ("ａｂｃ", "abc", "abc"),
        ("データ", "テ\u{3099}ータ", "データ"),
    ])
    func foldedMatchScoresLikeIdenticalMatch(query: String, text: String, identicalText: String) {
        #expect(matcher.score(query: query, in: text) == matcher.score(query: identicalText, in: identicalText))
    }

    // MARK: - ハイライト位置（元の文字列の Character オフセット）

    @Test("NFD の候補でも positions は元の文字列の Character オフセットで、濁点ごと 1 文字を指す")
    func positionsOnDecomposedTextPointToWholeCharacters() throws {
        let text = "資料/データ_ガイド.pdf".decomposedStringWithCanonicalMapping
        let characters = Array(text)

        let match = try #require(matcher.score(query: "がいど", in: text))

        #expect(match.positions == [7, 8, 9])
        #expect(String(match.positions.map { characters[$0] }) == "ガイド")
        // ハイライトする Character には結合文字（濁点）も含まれる
        #expect(characters[7].unicodeScalars.count == 2)
        #expect(matcher.score(query: "でーた", in: text)?.positions == [3, 4, 5])
    }

    @Test("半角カナの候補でも positions は元の文字列の Character オフセット")
    func positionsOnHalfwidthKatakana() {
        let text = "ｶﾞｲﾄﾞ_ｼﾘｮｳ.txt"

        #expect(matcher.score(query: "がいど", in: text)?.positions == [0, 1, 2])
        #expect(matcher.score(query: "しりょう", in: text)?.positions == [4, 5, 6, 7])
    }

    @Test("全角英字の候補でも CamelCase 境界を元の文字列で判定する")
    func camelCaseOnFullwidthText() {
        let camelCaseBonus = 8
        let headBonus = 16
        let gapPenaltyPerCharacterBeforeBoundary = 1

        let match = matcher.score(query: "fb", in: "ｆｏｏＢａｒ")

        #expect(match?.positions == [0, 3])
        #expect(match?.score == headBonus + camelCaseBonus - 2 * gapPenaltyPerCharacterBeforeBoundary)
    }

    // MARK: - 同一視しないもの

    @Test("濁点・半濁点の有無は区別する", arguments: [
        ("しりょう", "じりょう"), ("シリョウ", "ジリョウ"), ("はは", "ぱぱ"), ("かいと", "がいど"), ("ｼﾘｮｳ", "ジリョウ"),
    ])
    func voicedSoundMarksAreDistinguished(query: String, text: String) {
        #expect(matcher.score(query: query, in: text) == nil)
        #expect(matcher.score(query: query, in: text.decomposedStringWithCanonicalMapping) == nil)
    }

    @Test("小書きのかなは区別する: しりよう は しりょう にマッチしない")
    func smallKanaIsDistinguished() {
        #expect(matcher.score(query: "しりよう", in: "しりょう") == nil)
    }

    @Test("ローマ字には変換しない: shiryou は しりょう / 資料 にマッチしない")
    func romajiIsNotConverted() {
        #expect(matcher.score(query: "shiryou", in: "しりょう") == nil)
        #expect(matcher.score(query: "shiryou", in: "資料") == nil)
    }

    // MARK: - ラテン文字

    @Test("アクセントを落として比較する", arguments: [
        ("cafe", "café"),
        ("cafe", "cafe\u{301}"),
        ("café", "cafe"),
        ("CAFÉ", "café"),
    ])
    func latinDiacriticsAreIgnored(query: String, text: String) {
        #expect(matcher.score(query: query, in: text)?.positions == [0, 1, 2, 3])
    }

    @Test("大文字小文字を区別しない")
    func caseInsensitive() {
        #expect(matcher.score(query: "readme", in: "README.md")?.positions == [0, 1, 2, 3, 4, 5])
    }
}
