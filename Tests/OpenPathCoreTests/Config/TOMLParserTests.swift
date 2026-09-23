import Testing

import OpenPathCore

@Suite("TOMLParser: 正常系")
struct TOMLParserTests {
    /// DSN-002 §6 に記載の config.toml サンプル（そのまま転記）
    private static let designSampleTOML = """
        roots = ["~/repos", "~/Documents"]
        depth = 2
        include_files = false
        auto_confirm = false
        hotkey = "ctrl+shift+o"
        disabled_apps = ["com.apple.finder"]
        ignore = ["node_modules", ".git", "target", "DerivedData", ".build"]

        [ghq]
        enabled = true
        """

    @Test("DSN-002 §6 のサンプル TOML をパースできる")
    func parsesDesignSample() throws {
        let table = try TOMLParser.parse(Self.designSampleTOML)

        let expected: TOMLTable = [
            "roots": .stringArray(["~/repos", "~/Documents"]),
            "depth": .integer(2),
            "include_files": .bool(false),
            "auto_confirm": .bool(false),
            "hotkey": .string("ctrl+shift+o"),
            "disabled_apps": .stringArray(["com.apple.finder"]),
            "ignore": .stringArray(["node_modules", ".git", "target", "DerivedData", ".build"]),
            "ghq": .table(["enabled": .bool(true)]),
        ]
        #expect(table == expected)
    }

    @Test("空文字列は空のテーブルになる")
    func emptySource() throws {
        #expect(try TOMLParser.parse("") == [:])
    }

    @Test("空行・空白行・コメント行だけなら空のテーブルになる")
    func onlyBlankLinesAndComments() throws {
        let source = "\n   \n\t\n# コメント\n   # インデントされたコメント\n"

        #expect(try TOMLParser.parse(source) == [:])
    }

    @Test("行末コメントは値に含まれない")
    func trailingComments() throws {
        let source = """
            depth = 2 # 走査の深さ
            enabled = true# 空白なしのコメント
            hotkey = "ctrl+o" # 文字列の後のコメント
            roots = ["~/a"] # 配列の後のコメント
            [ghq] # テーブルヘッダの後のコメント
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "depth": .integer(2),
            "enabled": .bool(true),
            "hotkey": .string("ctrl+o"),
            "roots": .stringArray(["~/a"]),
            "ghq": .table([:]),
        ])
    }

    @Test("真偽値 true / false を読める", arguments: [("true", true), ("false", false)])
    func booleans(literal: String, expected: Bool) throws {
        #expect(try TOMLParser.parse("flag = \(literal)") == ["flag": .bool(expected)])
    }

    @Test(
        "符号付き 10 進整数を読める",
        arguments: [
            ("0", 0),
            ("42", 42),
            ("+7", 7),
            ("-17", -17),
            ("-0", 0),
            ("1_000", 1_000),
            ("-2_147_483_648", -2_147_483_648),
            ("9223372036854775807", Int.max),
            ("-9223372036854775808", Int.min),
        ]
    )
    func integers(literal: String, expected: Int) throws {
        #expect(try TOMLParser.parse("n = \(literal)") == ["n": .integer(expected)])
    }

    @Test("空の配列を読める")
    func emptyArray() throws {
        #expect(try TOMLParser.parse("a = []") == ["a": .stringArray([])])
        #expect(try TOMLParser.parse("a = [ \t ]") == ["a": .stringArray([])])
    }

    @Test("末尾カンマ付きの配列を読める")
    func arrayWithTrailingComma() throws {
        #expect(try TOMLParser.parse(#"a = ["x", "y",]"#) == ["a": .stringArray(["x", "y"])])
    }

    @Test("改行とコメントを含む複数行の配列を読める")
    func multilineArray() throws {
        let source = """
            ignore = [
              "node_modules", # 依存パッケージ
              # 行コメントだけの行

              ".git",
              'target',
            ]
            depth = 1
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "ignore": .stringArray(["node_modules", ".git", "target"]),
            "depth": .integer(1),
        ])
    }

    @Test("テーブルヘッダ以降のキーはそのテーブルに入り、ルートのキーと名前空間が分かれる")
    func tables() throws {
        let source = """
            enabled = false

            [ghq]
            enabled = true
            root = "~/ghq"

            [empty]

            [ other ]
            depth = 3
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "enabled": .bool(false),
            "ghq": .table(["enabled": .bool(true), "root": .string("~/ghq")]),
            "empty": .table([:]),
            "other": .table(["depth": .integer(3)]),
        ])
    }

    @Test("ベアキーには英数字・アンダースコア・ハイフンを使える")
    func bareKeys() throws {
        let source = """
            include_files = true
            auto-confirm = false
            key2 = 1
            1234 = 2
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "include_files": .bool(true),
            "auto-confirm": .bool(false),
            "key2": .integer(1),
            "1234": .integer(2),
        ])
    }

    @Test("クォートしたキーとテーブル名を使える")
    func quotedKeys() throws {
        let source = """
            "key with space" = 1
            'literal key' = 2
            "" = 3
            ["quoted table"]
            "a.b" = 4
            """

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "key with space": .integer(1),
            "literal key": .integer(2),
            "": .integer(3),
            "quoted table": .table(["a.b": .integer(4)]),
        ])
    }

    @Test("キー・= ・値の周りの空白とインデントは無視される")
    func whitespaceAroundTokens() throws {
        let source = "a=1\n  b\t=\t\"x\"  \n\t[ghq]\n    c   =   true   \n"

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "a": .integer(1),
            "b": .string("x"),
            "ghq": .table(["c": .bool(true)]),
        ])
    }

    @Test("CRLF の改行を扱える")
    func crlfLineEndings() throws {
        let source = "depth = 2\r\nroots = [\r\n  \"~/a\",\r\n]\r\n[ghq]\r\nenabled = true\r\n"

        let table = try TOMLParser.parse(source)

        #expect(table == [
            "depth": .integer(2),
            "roots": .stringArray(["~/a"]),
            "ghq": .table(["enabled": .bool(true)]),
        ])
    }

    @Test("先頭の BOM は読み飛ばす")
    func byteOrderMark() throws {
        #expect(try TOMLParser.parse("\u{FEFF}depth = 2") == ["depth": .integer(2)])
    }

    @Test("最終行に改行が無くても読める")
    func noTrailingNewline() throws {
        #expect(try TOMLParser.parse("a = \"x\"") == ["a": .string("x")])
        #expect(try TOMLParser.parse("a = [\"x\"]") == ["a": .stringArray(["x"])])
    }
}
