import Testing

import OpenPathCore

/// メニューの通知に出す説明の折り返し。幅は 1 文字 = 1 として測る。
@Suite("TextLineWrapper: 表示幅での折り返し")
struct TextLineWrapperTests {
    private static func characterCount(_ text: String) -> Double {
        Double(text.count)
    }

    private static func wrap(_ text: String, maxWidth: Double) -> [String] {
        TextLineWrapper.wrap(text, maxWidth: maxWidth, width: characterCount)
    }

    @Test("幅に収まれば 1 行のまま")
    func fitsInOneLine() {
        #expect(Self.wrap("設定ファイル", maxWidth: 10) == ["設定ファイル"])
    }

    @Test("空文字は行を作らない")
    func emptyText() {
        #expect(Self.wrap("", maxWidth: 10).isEmpty)
    }

    @Test("空白が無ければ幅を超える直前で折り返す")
    func breaksAtWidthWithoutSpaces() {
        #expect(Self.wrap("あいうえおかきくけこさし", maxWidth: 5) == ["あいうえお", "かきくけこ", "さし"])
    }

    @Test("空白があれば最後の空白で折り返し、空白は行に残さない")
    func prefersBreakingAtSpace() {
        let text = "設定ファイル /Users/tester/config.toml の書式"

        #expect(Self.wrap(text, maxWidth: 26) == ["設定ファイル", "/Users/tester/config.toml", "の書式"])
    }

    @Test("空白より長い語は幅で区切る")
    func breaksLongWord() {
        #expect(Self.wrap("ab /abcdefghij", maxWidth: 5) == ["ab", "/abcd", "efghi", "j"])
    }

    @Test("元の改行は保つ")
    func keepsExistingNewlines() {
        #expect(Self.wrap("一行目\n二行目", maxWidth: 10) == ["一行目", "二行目"])
    }

    @Test("幅より広い 1 文字でも 1 行に置いて先へ進む")
    func singleWideCharacter() {
        #expect(Self.wrap("あい", maxWidth: 0.5) == ["あ", "い"])
    }

    @Test("どの行も幅を超えない", arguments: [3.0, 7.0, 12.0, 20.0])
    func noLineExceedsWidth(maxWidth: Double) {
        let text = "設定ファイル /Users/tester/.config/openpath/config.toml の書式が誤っているため反映していません（3 行 5 列: = がありません）"

        let lines = Self.wrap(text, maxWidth: maxWidth)

        #expect(lines.allSatisfy { Self.characterCount($0) <= maxWidth })
        #expect(lines.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
    }
}
