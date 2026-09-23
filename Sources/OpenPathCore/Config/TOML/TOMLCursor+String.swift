/// 1 行の basic string（`"..."`）と literal string（`'...'`）の読み取り
extension TOMLCursor {
    private static let basicQuote: Unicode.Scalar = "\""
    private static let literalQuote: Unicode.Scalar = "'"
    private static let multilineBasicDelimiter = "\"\"\""
    private static let multilineLiteralDelimiter = "'''"
    private static let shortUnicodeEscapeDigitCount = 4
    private static let longUnicodeEscapeDigitCount = 8
    private static let hexRadix: UInt32 = 16
    private static let hexLetterBaseValue: UInt32 = 10

    /// `\uXXXX` / `\UXXXXXXXX` 以外のエスケープ（TOML 1.0）
    private static let simpleEscapes: [Unicode.Scalar: Unicode.Scalar] = [
        "b": "\u{08}",
        "t": "\t",
        "n": "\n",
        "f": "\u{0C}",
        "r": "\r",
        "\"": "\"",
        "\\": "\\",
    ]

    /// `"` の位置から basic string を読み、エスケープを解釈した値を返す
    mutating func readBasicString() throws(TOMLParseError) -> String {
        try readSingleLineString(
            quote: Self.basicQuote,
            multilineDelimiter: Self.multilineBasicDelimiter,
            interpretsEscapes: true
        )
    }

    /// `'` の位置から literal string を読み、中身をそのまま返す
    mutating func readLiteralString() throws(TOMLParseError) -> String {
        try readSingleLineString(
            quote: Self.literalQuote,
            multilineDelimiter: Self.multilineLiteralDelimiter,
            interpretsEscapes: false
        )
    }

    private mutating func readSingleLineString(
        quote: Unicode.Scalar,
        multilineDelimiter: String,
        interpretsEscapes: Bool
    ) throws(TOMLParseError) -> String {
        let start = position
        if hasPrefix(multilineDelimiter) {
            throw TOMLParseError(.unsupported(.multilineString), at: start)
        }
        advance()

        var value = String.UnicodeScalarView()
        while let scalar = current, !isAtNewline {
            switch scalar {
            case quote:
                advance()
                return String(value)
            case "\\" where interpretsEscapes:
                value.append(try readEscapeSequence())
            default:
                try rejectControlCharacter(scalar)
                value.append(scalar)
                advance()
            }
        }
        throw TOMLParseError(.unterminatedString, at: start)
    }

    private mutating func readEscapeSequence() throws(TOMLParseError) -> Unicode.Scalar {
        let escapeStart = position
        advance()

        guard let designator = current else {
            throw TOMLParseError(.invalidEscapeSequence, at: escapeStart)
        }
        if let escaped = Self.simpleEscapes[designator] {
            advance()
            return escaped
        }
        switch designator {
        case "u":
            advance()
            return try readUnicodeEscape(digitCount: Self.shortUnicodeEscapeDigitCount, escapeStart: escapeStart)
        case "U":
            advance()
            return try readUnicodeEscape(digitCount: Self.longUnicodeEscapeDigitCount, escapeStart: escapeStart)
        default:
            throw TOMLParseError(.invalidEscapeSequence, at: escapeStart)
        }
    }

    private mutating func readUnicodeEscape(
        digitCount: Int,
        escapeStart: TOMLSourcePosition
    ) throws(TOMLParseError) -> Unicode.Scalar {
        var codePoint: UInt32 = 0
        for _ in 0..<digitCount {
            guard let digit = current.flatMap(Self.hexDigitValue) else {
                throw TOMLParseError(.invalidEscapeSequence, at: escapeStart)
            }
            codePoint = codePoint * Self.hexRadix + digit
            advance()
        }
        // サロゲートや U+10FFFF を超える値は Unicode スカラーにならない
        guard let scalar = Unicode.Scalar(codePoint) else {
            throw TOMLParseError(.invalidEscapeSequence, at: escapeStart)
        }
        return scalar
    }

    /// ASCII の 16 進数字だけを受け付ける（`Character.hexDigitValue` は全角数字も受け付けるため使わない）
    private static func hexDigitValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar {
        case "0"..."9": scalar.value - ("0" as Unicode.Scalar).value
        case "a"..."f": scalar.value - ("a" as Unicode.Scalar).value + hexLetterBaseValue
        case "A"..."F": scalar.value - ("A" as Unicode.Scalar).value + hexLetterBaseValue
        default: nil
        }
    }
}
