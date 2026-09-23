import Testing

import OpenPathCore

@Suite("TOMLValue / TOMLParseError")
struct TOMLValueTests {
    private static let allCases: [TOMLValue] = [
        .string("s"),
        .bool(true),
        .integer(1),
        .stringArray(["a"]),
        .table(["k": .integer(1)]),
    ]

    @Test("各アクセサは一致するケースでのみ値を返す")
    func accessors() {
        #expect(TOMLValue.string("s").stringValue == "s")
        #expect(TOMLValue.bool(true).boolValue == true)
        #expect(TOMLValue.integer(1).integerValue == 1)
        #expect(TOMLValue.stringArray(["a"]).stringArrayValue == ["a"])
        #expect(TOMLValue.table(["k": .integer(1)]).tableValue == ["k": .integer(1)])

        #expect(Self.allCases.compactMap(\.stringValue).count == 1)
        #expect(Self.allCases.compactMap(\.boolValue).count == 1)
        #expect(Self.allCases.compactMap(\.integerValue).count == 1)
        #expect(Self.allCases.compactMap(\.stringArrayValue).count == 1)
        #expect(Self.allCases.compactMap(\.tableValue).count == 1)
    }

    @Test("エラーの説明は「行 列: 内容」の形式")
    func errorDescription() {
        let error = TOMLParseError(line: 3, column: 5, kind: .unterminatedString)

        #expect(error.description == "3 行 5 列: 文字列が閉じられていません")
    }

    @Test("エラーの説明にキー名やサポート外の構文名を含める")
    func errorDescriptionIncludesDetails() {
        let duplicate = TOMLParseError(line: 1, column: 1, kind: .duplicateKey("roots"))
        let unsupported = TOMLParseError(line: 1, column: 1, kind: .unsupported(.float))

        #expect(duplicate.description.contains("roots"))
        #expect(unsupported.description.contains("浮動小数点数"))
    }

    @Test("予期しない制御文字は説明中でエスケープして表示する")
    func errorDescriptionEscapesControlCharacters() {
        let error = TOMLParseError(line: 1, column: 1, kind: .unexpectedCharacter("\u{01}"))

        #expect(error.description.contains(#"'\u{01}'"#))
    }

    @Test("すべてのエラー種別に空でない説明がある")
    func everyKindHasDescription() {
        let features: [TOMLParseError.UnsupportedFeature] = [
            .nestedTable, .arrayOfTables, .inlineTable, .dottedKey, .float,
            .dateTime, .multilineString, .nonDecimalInteger, .nonStringArrayElement,
        ]
        let kinds: [TOMLParseError.Kind] = [
            .duplicateKey("k"), .unterminatedString, .unterminatedArray, .unterminatedTableHeader,
            .invalidEscapeSequence, .invalidKey, .missingEqualsSign, .missingValue, .invalidValue,
            .integerOutOfRange, .missingCommaOrClosingBracket, .unexpectedCharacter("x"),
        ] + features.map(TOMLParseError.Kind.unsupported)
        let prefix = "1 行 1 列: "

        let descriptions = kinds.map { TOMLParseError(line: 1, column: 1, kind: $0).description }

        #expect(descriptions.allSatisfy { $0.hasPrefix(prefix) && $0.count > prefix.count })
        #expect(Set(descriptions).count == descriptions.count)
    }
}
