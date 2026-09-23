import Testing

import OpenPathCore

/// TOML として正しいが、config.toml に不要なためサポートしない構文。
/// 黙って誤読しないよう、構文ごとに明示的なエラーになることを確認する。
@Suite("TOMLParser: サポート外の構文")
struct TOMLParserUnsupportedTests {
    @Test(
        "ネストしたテーブル・テーブルの配列・ドット区切りキーはエラー",
        arguments: [
            TOMLErrorCase("[a.b]", line: 1, column: 1, .unsupported(.nestedTable)),
            TOMLErrorCase("[ ghq . sub ]", line: 1, column: 1, .unsupported(.nestedTable)),
            TOMLErrorCase("[[items]]", line: 1, column: 1, .unsupported(.arrayOfTables)),
            TOMLErrorCase("a.b = 1", line: 1, column: 1, .unsupported(.dottedKey)),
            TOMLErrorCase("[ghq]\n\"x\" . y = 1", line: 2, column: 1, .unsupported(.dottedKey)),
        ]
    )
    func tableStructures(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "インラインテーブルはエラー",
        arguments: [
            TOMLErrorCase("ghq = { enabled = true }", line: 1, column: 7, .unsupported(.inlineTable)),
            TOMLErrorCase("a = [{ b = 1 }]", line: 1, column: 6, .unsupported(.inlineTable)),
        ]
    )
    func inlineTables(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "浮動小数点数はエラー",
        arguments: [
            TOMLErrorCase("a = 3.14", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = -0.5", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = 1e5", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = 6.02E+23", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = inf", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = -inf", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = nan", line: 1, column: 5, .unsupported(.float)),
            TOMLErrorCase("a = [1.5]", line: 1, column: 6, .unsupported(.float)),
        ]
    )
    func floats(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "日付・時刻はエラー",
        arguments: [
            TOMLErrorCase("a = 1979-05-27", line: 1, column: 5, .unsupported(.dateTime)),
            TOMLErrorCase("a = 07:32:00", line: 1, column: 5, .unsupported(.dateTime)),
            TOMLErrorCase("a = 1979-05-27T07:32:00Z", line: 1, column: 5, .unsupported(.dateTime)),
            TOMLErrorCase("a = 1979-05-27 07:32:00", line: 1, column: 5, .unsupported(.dateTime)),
        ]
    )
    func dateTimes(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "複数行文字列はエラー",
        arguments: [
            TOMLErrorCase(#"a = """x""""#, line: 1, column: 5, .unsupported(.multilineString)),
            TOMLErrorCase("a = '''x'''", line: 1, column: 5, .unsupported(.multilineString)),
        ]
    )
    func multilineStrings(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "10 進数以外の整数はエラー",
        arguments: [
            TOMLErrorCase("a = 0x1F", line: 1, column: 5, .unsupported(.nonDecimalInteger)),
            TOMLErrorCase("a = 0o17", line: 1, column: 5, .unsupported(.nonDecimalInteger)),
            TOMLErrorCase("a = 0b101", line: 1, column: 5, .unsupported(.nonDecimalInteger)),
        ]
    )
    func nonDecimalIntegers(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "文字列以外を要素に持つ配列はエラー（位置はその要素）",
        arguments: [
            TOMLErrorCase("a = [1, 2]", line: 1, column: 6, .unsupported(.nonStringArrayElement)),
            TOMLErrorCase(#"a = ["x", true]"#, line: 1, column: 11, .unsupported(.nonStringArrayElement)),
            TOMLErrorCase(#"a = [["x"]]"#, line: 1, column: 6, .unsupported(.nonStringArrayElement)),
            TOMLErrorCase("a = [\n  \"x\",\n  2,\n]", line: 3, column: 3, .unsupported(.nonStringArrayElement)),
        ]
    )
    func nonStringArrays(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }
}
