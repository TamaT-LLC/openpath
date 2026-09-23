import Testing

import OpenPathCore

@Suite("TextNormalizer（正規化の差し込み口）")
struct TextNormalizerTests {
    /// 差し込み口の検証用。表にある Character を置き換え、それ以外は小文字化する。
    /// 1 文字を複数文字に展開する正規化（例: ß → ss）でも元の位置に戻せることを確かめる。
    private struct MappingNormalizer: TextNormalizer {
        let table: [Character: String]

        func normalize(_ text: String) -> NormalizedText {
            var characters: [Character] = []
            var sourceOffsets: [Int] = []
            for (offset, character) in text.enumerated() {
                for normalized in table[character] ?? character.lowercased() {
                    characters.append(normalized)
                    sourceOffsets.append(offset)
                }
            }
            return NormalizedText(characters: characters, sourceOffsets: sourceOffsets)
        }
    }

    @Test("LowercaseNormalizer は Character 単位で小文字化し、元のオフセットを保持する")
    func lowercaseNormalizerKeepsOffsets() {
        let normalized = LowercaseNormalizer().normalize("AbÉ/資料")

        #expect(normalized.characters == ["a", "b", "é", "/", "資", "料"])
        #expect(normalized.sourceOffsets == [0, 1, 2, 3, 4, 5])
    }

    @Test("既定の正規化は JapaneseAwareNormalizer（かな・幅を同一視する）")
    func defaultNormalizerIsJapaneseAware() throws {
        let defaultMatcher = FuzzyMatcher()
        let explicitMatcher = FuzzyMatcher(normalizer: JapaneseAwareNormalizer())
        let lowercaseMatcher = FuzzyMatcher(normalizer: LowercaseNormalizer())

        let match = try #require(defaultMatcher.score(query: "しりょう", in: "ｼﾘｮｳ"))

        #expect(match == explicitMatcher.score(query: "しりょう", in: "ｼﾘｮｳ"))
        #expect(lowercaseMatcher.score(query: "しりょう", in: "ｼﾘｮｳ") == nil)
    }

    @Test("差し込んだ正規化はクエリと対象の両方に適用される")
    func injectedNormalizerAppliesToBothSides() {
        let matcher = FuzzyMatcher(normalizer: MappingNormalizer(table: ["0": "o"]))

        #expect(matcher.score(query: "foo", in: "f00")?.positions == [0, 1, 2])
        #expect(matcher.score(query: "f00", in: "foo")?.positions == [0, 1, 2])
    }

    @Test("1 文字が複数文字に展開されても positions は元の Character オフセットに戻る")
    func expandedCharactersMapBackToSourceOffset() {
        let matcher = FuzzyMatcher(normalizer: MappingNormalizer(table: ["ß": "ss"]))

        #expect(matcher.score(query: "ss", in: "aß")?.positions == [1])
        #expect(matcher.score(query: "strasse", in: "Straße")?.positions == [0, 1, 2, 3, 4, 5])
    }

    @Test("展開された 2 文字目以降には位置ボーナスを付けない")
    func expandedTailCharactersGetNoPositionalBonus() {
        let separatorBonus = 12
        let consecutiveBonus = 6
        let matcher = FuzzyMatcher(normalizer: MappingNormalizer(table: ["ß": "ss"]))

        // 「ß」は「-」直後なので、展開後の 1 文字目の s だけが区切りボーナスを得る
        let match = matcher.score(query: "ss", in: "a-ß")

        #expect(match?.positions == [2])
        #expect(match?.score == separatorBonus + consecutiveBonus)
    }
}
