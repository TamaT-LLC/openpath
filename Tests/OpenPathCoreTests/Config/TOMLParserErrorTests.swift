import Testing

import OpenPathCore

@Suite("TOMLParser: 構文エラー")
struct TOMLParserErrorTests {
    @Test(
        "キーやテーブル名の重複はエラー（位置は後から出現したキー）",
        arguments: [
            TOMLErrorCase("a = 1\na = 2", line: 2, column: 1, .duplicateKey("a")),
            TOMLErrorCase("\"a\" = 1\na = 2", line: 2, column: 1, .duplicateKey("a")),
            TOMLErrorCase("[ghq]\nenabled = true\nenabled = false", line: 3, column: 1, .duplicateKey("enabled")),
            TOMLErrorCase("[ghq]\n[ghq]", line: 2, column: 2, .duplicateKey("ghq")),
            TOMLErrorCase("ghq = 1\n[ghq]", line: 2, column: 2, .duplicateKey("ghq")),
        ]
    )
    func duplicateKeys(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "閉じていない文字列はエラー（位置は開き引用符）",
        arguments: [
            TOMLErrorCase(#"a = "abc"#, line: 1, column: 5, .unterminatedString),
            TOMLErrorCase("a = \"abc\nb = 1", line: 1, column: 5, .unterminatedString),
            TOMLErrorCase("a = 'abc", line: 1, column: 5, .unterminatedString),
            TOMLErrorCase("a = 'abc\nb = 1", line: 1, column: 5, .unterminatedString),
            TOMLErrorCase(#"roots = ["a", "b"#, line: 1, column: 15, .unterminatedString),
            TOMLErrorCase(#""key = 1"#, line: 1, column: 1, .unterminatedString),
        ]
    )
    func unterminatedStrings(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "閉じていない配列はエラー（位置は開き括弧）",
        arguments: [
            TOMLErrorCase("roots = [", line: 1, column: 9, .unterminatedArray),
            TOMLErrorCase(#"roots = ["a","#, line: 1, column: 9, .unterminatedArray),
            TOMLErrorCase("x = 1\nroots = [\n  \"a\",\n  # comment\n", line: 2, column: 9, .unterminatedArray),
        ]
    )
    func unterminatedArrays(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "配列要素の後に , も ] も無いとエラー",
        arguments: [
            TOMLErrorCase(#"roots = ["a" "b"]"#, line: 1, column: 14, .missingCommaOrClosingBracket),
            TOMLErrorCase("roots = [\"a\"\ndepth = 2", line: 2, column: 1, .missingCommaOrClosingBracket),
        ]
    )
    func missingArraySeparators(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "不正なエスケープシーケンスはエラー（位置はバックスラッシュ）",
        arguments: [
            TOMLErrorCase(#"a = "\x41""#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\uZZZZ""#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\u12""#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\uD800""#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\U00110000""#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\"#, line: 1, column: 6, .invalidEscapeSequence),
            TOMLErrorCase(#"a = "\u００４１""#, line: 1, column: 6, .invalidEscapeSequence),
        ]
    )
    func invalidEscapes(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "値として解釈できない語はエラー",
        arguments: [
            TOMLErrorCase("a = abc", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("hotkey = ctrl+shift+o", line: 1, column: 10, .invalidValue),
            TOMLErrorCase("a = True", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = trueish", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = 02", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = 1__0", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = 1_", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = _1", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = +", line: 1, column: 5, .invalidValue),
            TOMLErrorCase("a = ３", line: 1, column: 5, .invalidValue),
        ]
    )
    func invalidValues(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "Int の範囲を超える整数はエラー",
        arguments: [
            TOMLErrorCase("a = 9223372036854775808", line: 1, column: 5, .integerOutOfRange),
            TOMLErrorCase("a = -9223372036854775809", line: 1, column: 5, .integerOutOfRange),
        ]
    )
    func integerOutOfRange(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "= の後に値が無いとエラー",
        arguments: [
            TOMLErrorCase("a =", line: 1, column: 4, .missingValue),
            TOMLErrorCase("a = # comment", line: 1, column: 5, .missingValue),
            TOMLErrorCase("a =\nb = 1", line: 1, column: 4, .missingValue),
        ]
    )
    func missingValues(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "キーの後に = が無いとエラー",
        arguments: [
            TOMLErrorCase(#"a "b""#, line: 1, column: 3, .missingEqualsSign),
            TOMLErrorCase("a", line: 1, column: 2, .missingEqualsSign),
            TOMLErrorCase("a b = 1", line: 1, column: 3, .missingEqualsSign),
        ]
    )
    func missingEqualsSigns(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "キーとして不正な書き出しはエラー",
        arguments: [
            TOMLErrorCase("= 1", line: 1, column: 1, .invalidKey),
            TOMLErrorCase("@key = 1", line: 1, column: 1, .invalidKey),
            TOMLErrorCase("キー = 1", line: 1, column: 1, .invalidKey),
            TOMLErrorCase("[]", line: 1, column: 2, .invalidKey),
        ]
    )
    func invalidKeys(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "] で閉じていないテーブルヘッダはエラー（位置は開き括弧）",
        arguments: [
            TOMLErrorCase("[ghq", line: 1, column: 1, .unterminatedTableHeader),
            TOMLErrorCase("[ghq\nenabled = true", line: 1, column: 1, .unterminatedTableHeader),
            TOMLErrorCase("[ghq # comment", line: 1, column: 1, .unterminatedTableHeader),
        ]
    )
    func unterminatedTableHeaders(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "値やテーブルヘッダの後ろの余分な文字はエラー",
        arguments: [
            TOMLErrorCase("a = 1 2", line: 1, column: 7, .unexpectedCharacter("2")),
            TOMLErrorCase(#"a = "x" "y""#, line: 1, column: 9, .unexpectedCharacter("\"")),
            TOMLErrorCase(#"a = ["x"] y"#, line: 1, column: 11, .unexpectedCharacter("y")),
            TOMLErrorCase("a = ,", line: 1, column: 5, .unexpectedCharacter(",")),
            TOMLErrorCase("a = [,]", line: 1, column: 6, .unexpectedCharacter(",")),
            TOMLErrorCase("[ghq] enabled = true", line: 1, column: 7, .unexpectedCharacter("e")),
            TOMLErrorCase("[ghq x]", line: 1, column: 6, .unexpectedCharacter("x")),
        ]
    )
    func unexpectedCharacters(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "文字列・コメント内の制御文字と単独の CR はエラー",
        arguments: [
            TOMLErrorCase("a = \"x\u{01}y\"", line: 1, column: 7, .unexpectedCharacter("\u{01}")),
            TOMLErrorCase("a = 'x\u{7F}'", line: 1, column: 7, .unexpectedCharacter("\u{7F}")),
            TOMLErrorCase("# comment \u{00}\na = 1", line: 1, column: 11, .unexpectedCharacter("\u{00}")),
            TOMLErrorCase("a = 1\rb = 2", line: 1, column: 6, .unexpectedCharacter("\r")),
        ]
    )
    func controlCharacters(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }

    @Test(
        "行番号・列番号を正しく数える",
        arguments: [
            // CRLF は 1 つの改行として数える
            TOMLErrorCase("a = 1\r\nb = 2\r\nc = @", line: 3, column: 5, .invalidValue),
            // 複数行の配列の改行も行番号に含める
            TOMLErrorCase("roots = [\n  \"a\",\n  \"b\",\n]\ndepth = x", line: 5, column: 9, .invalidValue),
            // 列は Unicode スカラー単位で数える（日本語も 1 文字 = 1 列）
            TOMLErrorCase(#""日本語" = x"#, line: 1, column: 9, .invalidValue),
            TOMLErrorCase(#"a = "日本\q""#, line: 1, column: 8, .invalidEscapeSequence),
            // 先頭の BOM は列に数えない
            TOMLErrorCase("\u{FEFF}a = x", line: 1, column: 5, .invalidValue),
        ]
    )
    func positions(_ testCase: TOMLErrorCase) {
        testCase.verify()
    }
}
