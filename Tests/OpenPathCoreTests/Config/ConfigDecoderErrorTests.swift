import Testing

import OpenPathCore

/// デコードエラーのテストケース。TOML の入力と、期待するキーパス・種別の組。
struct ConfigErrorCase: Sendable, CustomTestStringConvertible {
    let source: String
    let expected: ConfigDecodingError

    init(_ source: String, key: String, _ kind: ConfigDecodingError.Kind) {
        self.source = source
        self.expected = ConfigDecodingError(key: key, kind: kind)
    }

    var testDescription: String { source.debugDescription }

    /// 入力をパースしてデコードし、期待どおりのエラーになることを検証する
    func verify(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let table = try TOMLParser.parse(source)
        #expect(throws: expected, sourceLocation: sourceLocation) {
            try ConfigTestSupport.decoder.decode(table)
        }
    }
}

@Suite("ConfigDecoder: エラー")
struct ConfigDecoderErrorTests {
    @Test(
        "型が合わない値はキーパス付きのエラー",
        arguments: [
            ConfigErrorCase(#"roots = "~/repos""#, key: "roots", .typeMismatch(expected: .stringArray, actual: .string)),
            ConfigErrorCase("roots = 1", key: "roots", .typeMismatch(expected: .stringArray, actual: .integer)),
            ConfigErrorCase("[roots]", key: "roots", .typeMismatch(expected: .stringArray, actual: .table)),
            ConfigErrorCase(#"depth = "2""#, key: "depth", .typeMismatch(expected: .integer, actual: .string)),
            ConfigErrorCase("depth = true", key: "depth", .typeMismatch(expected: .integer, actual: .bool)),
            ConfigErrorCase(#"include_files = "yes""#, key: "include_files", .typeMismatch(expected: .bool, actual: .string)),
            ConfigErrorCase("auto_confirm = 1", key: "auto_confirm", .typeMismatch(expected: .bool, actual: .integer)),
            ConfigErrorCase(#"hotkey = ["ctrl", "o"]"#, key: "hotkey", .typeMismatch(expected: .string, actual: .stringArray)),
            ConfigErrorCase(
                #"disabled_apps = "com.apple.finder""#,
                key: "disabled_apps",
                .typeMismatch(expected: .stringArray, actual: .string)
            ),
            ConfigErrorCase("ignore = false", key: "ignore", .typeMismatch(expected: .stringArray, actual: .bool)),
            ConfigErrorCase("ghq = true", key: "ghq", .typeMismatch(expected: .table, actual: .bool)),
            ConfigErrorCase("[ghq]\nenabled = \"true\"", key: "ghq.enabled", .typeMismatch(expected: .bool, actual: .string)),
            ConfigErrorCase("[ghq]\nenabled = 1", key: "ghq.enabled", .typeMismatch(expected: .bool, actual: .integer)),
        ]
    )
    func typeMismatch(_ testCase: ConfigErrorCase) throws {
        try testCase.verify()
    }

    @Test(
        "depth が負ならエラー",
        arguments: [
            ConfigErrorCase("depth = -1", key: "depth", .belowMinimum(value: -1, minimum: 0)),
            ConfigErrorCase("depth = -100", key: "depth", .belowMinimum(value: -100, minimum: 0)),
        ]
    )
    func negativeDepth(_ testCase: ConfigErrorCase) throws {
        try testCase.verify()
    }

    @Test(
        "roots に絶対パスへ解決できないパスがあればエラー（そのパスを報告する）",
        arguments: [
            ConfigErrorCase(#"roots = ["repos"]"#, key: "roots", .invalidRootPath("repos")),
            ConfigErrorCase(#"roots = ["~/ok", ""]"#, key: "roots", .invalidRootPath("")),
            ConfigErrorCase(#"roots = ["~other/src"]"#, key: "roots", .invalidRootPath("~other/src")),
        ]
    )
    func invalidRootPath(_ testCase: ConfigErrorCase) throws {
        try testCase.verify()
    }

    @Test(
        "hotkey がパースできなければ HotkeyParseError を包んだエラー",
        arguments: [
            ConfigErrorCase(#"hotkey = "o""#, key: "hotkey", .invalidHotkey(.missingModifier)),
            ConfigErrorCase(#"hotkey = "ctrl+foo""#, key: "hotkey", .invalidHotkey(.unknownKey("foo"))),
            ConfigErrorCase(#"hotkey = """#, key: "hotkey", .invalidHotkey(.empty)),
        ]
    )
    func invalidHotkey(_ testCase: ConfigErrorCase) throws {
        try testCase.verify()
    }

    @Test(
        "誤りが複数あれば roots → depth → … → ghq の定義順で最初の 1 件を報告する",
        arguments: [
            ConfigErrorCase("depth = -1\nhotkey = \"o\"\nroots = [\"x\"]", key: "roots", .invalidRootPath("x")),
            ConfigErrorCase("unknown = 1\nhotkey = \"o\"\n[ghq]\nenabled = 1", key: "hotkey", .invalidHotkey(.missingModifier)),
        ]
    )
    func reportsFirstErrorInDefinitionOrder(_ testCase: ConfigErrorCase) throws {
        try testCase.verify()
    }
}

@Suite("ConfigDecodingError: メッセージ")
struct ConfigDecodingErrorDescriptionTests {
    @Test(
        "description はキーパスと理由を含む",
        arguments: [
            (
                ConfigDecodingError(key: "depth", kind: .typeMismatch(expected: .integer, actual: .string)),
                "設定 'depth': 整数を指定してください（実際の値は文字列）"
            ),
            (
                ConfigDecodingError(key: "depth", kind: .belowMinimum(value: -1, minimum: 0)),
                "設定 'depth': 0 以上を指定してください（実際の値は -1）"
            ),
            (
                ConfigDecodingError(key: "roots", kind: .invalidRootPath("repos")),
                "設定 'roots': 'repos' は / で始まる絶対パス、~、または ~/ で始まるパスで指定してください（~user 形式は使えません）"
            ),
            (
                ConfigDecodingError(key: "roots", kind: .invalidRootPath("~other/src")),
                "設定 'roots': '~other/src' は / で始まる絶対パス、~、または ~/ で始まるパスで指定してください（~user 形式は使えません）"
            ),
            (
                ConfigDecodingError(key: "hotkey", kind: .invalidHotkey(.missingModifier)),
                "設定 'hotkey': 修飾キー（ctrl / opt / cmd など）が必要です"
            ),
        ]
    )
    func description(error: ConfigDecodingError, expected: String) {
        #expect(error.description == expected)
    }

    @Test("型の名前は種類ごとに異なる")
    func typeNamesAreDistinct() {
        let descriptions = ConfigValueType.allCases.map { type in
            ConfigDecodingError(key: "k", kind: .typeMismatch(expected: type, actual: type)).description
        }

        #expect(Set(descriptions).count == ConfigValueType.allCases.count)
    }
}
