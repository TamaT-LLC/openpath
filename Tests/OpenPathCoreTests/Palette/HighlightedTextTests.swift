import Testing

import OpenPathCore

@Suite("HighlightedText")
struct HighlightedTextTests {
    private typealias Segment = HighlightedText.Segment

    @Test("ハイライトがなければ全体が 1 つの非ハイライト区間になる")
    func noHighlightsYieldsSinglePlainSegment() {
        let text = HighlightedText("fern-docs")

        #expect(text.segments == [Segment(text: "fern-docs", isHighlighted: false)])
    }

    @Test("連続するハイライト位置は 1 つの区間にまとめる")
    func consecutiveOffsetsAreMerged() {
        let text = HighlightedText("fern-docs", highlightedOffsets: [0, 1, 2, 3])

        #expect(text.segments == [
            Segment(text: "fern", isHighlighted: true),
            Segment(text: "-docs", isHighlighted: false),
        ])
    }

    @Test("飛び飛びのハイライト位置は交互の区間になる")
    func scatteredOffsetsAlternate() {
        let text = HighlightedText("abcde", highlightedOffsets: [0, 2, 4])

        #expect(text.segments == [
            Segment(text: "a", isHighlighted: true),
            Segment(text: "b", isHighlighted: false),
            Segment(text: "c", isHighlighted: true),
            Segment(text: "d", isHighlighted: false),
            Segment(text: "e", isHighlighted: true),
        ])
    }

    @Test("ハイライト位置は昇順・重複なしに揃え、範囲外は捨てる")
    func offsetsAreNormalized() {
        let text = HighlightedText("abc", highlightedOffsets: [2, 0, 2, -1, 3, 99])

        #expect(text.highlightedOffsets == [0, 2])
    }

    @Test("空文字列は区間を持たない")
    func emptyTextHasNoSegments() {
        let text = HighlightedText("", highlightedOffsets: [0])

        #expect(text.highlightedOffsets.isEmpty)
        #expect(text.segments.isEmpty)
    }

    @Test("日本語は Character 単位でハイライトする")
    func japaneseIsHighlightedPerCharacter() {
        let text = HighlightedText("資料フォルダ", highlightedOffsets: [0, 1, 5])

        #expect(text.segments == [
            Segment(text: "資料", isHighlighted: true),
            Segment(text: "フォル", isHighlighted: false),
            Segment(text: "ダ", isHighlighted: true),
        ])
    }

    @Test("濁点が分解された NFD の文字も 1 Character として扱う")
    func decomposedKanaIsOneCharacter() {
        // 「がっこう」の「が」を NFD（か + 結合用濁点）で表す。HFS+ 由来のパス名で起こり得る
        let decomposed = "\u{304B}\u{3099}っこう"
        let text = HighlightedText(decomposed, highlightedOffsets: [0, 4])

        #expect(text.highlightedOffsets == [0])
        #expect(text.segments == [
            Segment(text: "\u{304B}\u{3099}", isHighlighted: true),
            Segment(text: "っこう", isHighlighted: false),
        ])
    }
}
