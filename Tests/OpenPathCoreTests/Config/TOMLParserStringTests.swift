import Testing

import OpenPathCore

@Suite("TOMLParser: 文字列")
struct TOMLParserStringTests {
    @Test("basic string を読める")
    func basicString() throws {
        #expect(try TOMLParser.parse(#"hotkey = "ctrl+shift+o""#) == ["hotkey": .string("ctrl+shift+o")])
    }

    @Test("literal string を読める")
    func literalString() throws {
        #expect(try TOMLParser.parse("hotkey = 'ctrl+shift+o'") == ["hotkey": .string("ctrl+shift+o")])
    }

    @Test("空文字列を読める")
    func emptyStrings() throws {
        #expect(try TOMLParser.parse(#"a = """#) == ["a": .string("")])
        #expect(try TOMLParser.parse("a = ''") == ["a": .string("")])
    }

    @Test(
        "basic string のエスケープシーケンスを解釈する",
        arguments: [
            (#"\""#, "\""),
            (#"\\"#, "\\"),
            (#"\n"#, "\n"),
            (#"\t"#, "\t"),
            (#"\r"#, "\r"),
            (#"\b"#, "\u{08}"),
            (#"\f"#, "\u{0C}"),
            (#"\u00E9"#, "é"),
            // 16 進の英字は小文字も受け付ける
            (#"\u00e9"#, "é"),
            (#"\u3042"#, "あ"),
            (#"\U0001F600"#, "😀"),
        ]
    )
    func escapeSequences(escaped: String, expected: String) throws {
        let table = try TOMLParser.parse("a = \"[\(escaped)]\"")

        #expect(table == ["a": .string("[\(expected)]")])
    }

    @Test("literal string はバックスラッシュをそのまま残す")
    func literalStringKeepsBackslashes() throws {
        let table = try TOMLParser.parse(#"path = 'C:\Users\name\n'"#)

        #expect(table == ["path": .string(#"C:\Users\name\n"#)])
    }

    @Test("文字列内の反対側の引用符と # はそのまま文字として扱う")
    func quotesAndHashInsideStrings() throws {
        let source = """
            a = "it's # not a comment"
            b = 'say "hi" # here'
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "a": .string("it's # not a comment"),
            "b": .string(#"say "hi" # here"#),
        ])
    }

    @Test("文字列内のタブはそのまま読める")
    func tabInsideString() throws {
        #expect(try TOMLParser.parse("a = \"x\ty\"") == ["a": .string("x\ty")])
    }

    @Test("日本語を含む文字列値を読める")
    func japaneseStringValues() throws {
        let source = """
            root = "~/書類/プロジェクト"
            label = 'ひらがな・カタカナ・漢字 🗂'
            roots = ["~/デスクトップ", '~/ダウンロード']
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "root": .string("~/書類/プロジェクト"),
            "label": .string("ひらがな・カタカナ・漢字 🗂"),
            "roots": .stringArray(["~/デスクトップ", "~/ダウンロード"]),
        ])
    }

    @Test("日本語のクォート付きキーとテーブル名を読める")
    func japaneseQuotedKeys() throws {
        let source = """
            "表示名" = "開発"
            ["設定"]
            '説明' = "日本語の説明"
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "表示名": .string("開発"),
            "設定": .table(["説明": .string("日本語の説明")]),
        ])
    }

    @Test("結合文字を含む文字列を Unicode スカラーのまま保持する")
    func combiningCharacters() throws {
        // 開き引用符の直後の結合濁点は Character 単位だと引用符と 1 文字に結合してしまうケース。
        // 後半は NFD の「が」（か + 結合濁点）。正規化はパーサの責務ではないため入力のまま返す
        let decomposed = "\u{3099}\u{304B}\u{3099}"

        let table = try TOMLParser.parse("a = \"\(decomposed)\"")

        // String の == は正規等価で比較するため、スカラー列で比較する
        #expect(table["a"]?.stringValue?.unicodeScalars.elementsEqual(decomposed.unicodeScalars) == true)
    }
}
