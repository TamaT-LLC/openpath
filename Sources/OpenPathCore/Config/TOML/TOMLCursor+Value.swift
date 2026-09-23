/// `=` の右辺の値の読み取り
extension TOMLCursor {
    /// クォートしない値（真偽値・数値・日時）の終わりを示す文字
    private static let bareValueTerminators: Set<Unicode.Scalar> = [
        " ", "\t", "\n", "\r", "#", ",", "=", "[", "]", "{", "}", "\"", "'",
    ]

    /// 現在位置から値を 1 つ読む
    mutating func readValue() throws(TOMLParseError) -> TOMLValue {
        let start = position
        guard let scalar = current, !isAtNewline, scalar != "#" else {
            throw TOMLParseError(.missingValue, at: start)
        }
        switch scalar {
        case "\"":
            return .string(try readBasicString())
        case "'":
            return .string(try readLiteralString())
        case "[":
            return .stringArray(try readStringArray())
        case "{":
            throw TOMLParseError(.unsupported(.inlineTable), at: start)
        case _ where Self.bareValueTerminators.contains(scalar):
            throw TOMLParseError(.unexpectedCharacter(scalar), at: start)
        default:
            return try readBareValue()
        }
    }

    // MARK: - 配列

    private mutating func readStringArray() throws(TOMLParseError) -> [String] {
        let arrayStart = position
        advance()

        var elements: [String] = []
        try skipArrayTrivia(arrayStart: arrayStart)
        while current != "]" {
            elements.append(try readArrayElement())
            try skipArrayTrivia(arrayStart: arrayStart)
            if current == "]" {
                break
            }
            guard current == "," else {
                throw TOMLParseError(.missingCommaOrClosingBracket, at: position)
            }
            advance()
            // 末尾カンマの後は ] で閉じてよい
            try skipArrayTrivia(arrayStart: arrayStart)
        }
        advance()
        return elements
    }

    /// 配列内の要素間にある空白・改行・コメントを読み飛ばす。途中でソースが終われば未閉鎖のエラー
    private mutating func skipArrayTrivia(arrayStart: TOMLSourcePosition) throws(TOMLParseError) {
        repeat {
            skipWhitespace()
            try skipComment()
        } while consumeNewline()

        if isAtEnd {
            throw TOMLParseError(.unterminatedArray, at: arrayStart)
        }
    }

    private mutating func readArrayElement() throws(TOMLParseError) -> String {
        let elementStart = position
        switch current {
        case "\"":
            return try readBasicString()
        case "'":
            return try readLiteralString()
        case "[":
            // 入れ子の配列は再帰せずに打ち切る（深い入れ子でのスタック消費を避ける）
            throw TOMLParseError(.unsupported(.nonStringArrayElement), at: elementStart)
        default:
            // 浮動小数などの個別のエラーを優先するため、値として一度読んでから打ち切る
            _ = try readValue()
            throw TOMLParseError(.unsupported(.nonStringArrayElement), at: elementStart)
        }
    }

    // MARK: - クォートしない値

    /// 終端文字までを 1 語として読み、値として解釈する。先頭が終端文字でないことは呼び出し元で確認済み
    private mutating func readBareValue() throws(TOMLParseError) -> TOMLValue {
        let start = position
        var token = String.UnicodeScalarView()
        while let scalar = current, !Self.bareValueTerminators.contains(scalar) {
            token.append(scalar)
            advance()
        }
        return try Self.interpretBareValue(String(token), at: start)
    }

    private static func interpretBareValue(
        _ token: String,
        at start: TOMLSourcePosition
    ) throws(TOMLParseError) -> TOMLValue {
        switch token {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        default:
            break
        }

        // 先頭の 0 は不可、_ は数字の間に 1 つだけ（TOML 1.0）
        if token.wholeMatch(of: /[+-]?(?:0|[1-9](?:_?[0-9])*)/) != nil {
            guard let integer = Int(token.filter { $0 != "_" }) else {
                throw TOMLParseError(.integerOutOfRange, at: start)
            }
            return .integer(integer)
        }
        if let feature = unsupportedFeature(ofBareToken: token) {
            throw TOMLParseError(.unsupported(feature), at: start)
        }
        throw TOMLParseError(.invalidValue, at: start)
    }

    /// TOML としては正しいがサポートしない値の形か判定する。
    /// 不正な値として一括で弾くより、何がサポート外かを伝えるため形だけで大まかに判定する
    private static func unsupportedFeature(ofBareToken token: String) -> TOMLParseError.UnsupportedFeature? {
        if token.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}.*|[0-9]{2}:[0-9]{2}.*/) != nil {
            return .dateTime
        }
        if token.wholeMatch(of: /0[xob].*/) != nil {
            return .nonDecimalInteger
        }
        let isSpecialFloat = token.wholeMatch(of: /[+-]?(?:inf|nan)/) != nil
        let isNumericFloat = token.wholeMatch(of: /[+-]?[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?/) != nil
            && token.contains { $0 == "." || $0 == "e" || $0 == "E" }
        if isSpecialFloat || isNumericFloat {
            return .float
        }
        return nil
    }
}
