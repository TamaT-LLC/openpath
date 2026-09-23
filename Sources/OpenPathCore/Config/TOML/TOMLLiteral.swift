/// TOML の値を書き出す。TOMLParser で読み戻せる形（1 行の basic string と文字列の配列）だけを扱う。
enum TOMLLiteral {
    private static let quote = "\""
    private static let arrayElementSeparator = ", "
    private static let lastC0Control: Unicode.Scalar = "\u{1F}"
    private static let delete: Unicode.Scalar = "\u{7F}"
    private static let unicodeEscapePrefix = "\\u"
    private static let unicodeEscapeDigitCount = 4
    private static let hexRadix = 16

    /// 短い表記のあるエスケープ（TOML 1.0）
    private static let shortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"",
        "\\": "\\\\",
        "\u{08}": "\\b",
        "\t": "\\t",
        "\n": "\\n",
        "\u{0C}": "\\f",
        "\r": "\\r",
    ]

    /// basic string（`"..."`）。basic string に直接書けない制御文字はエスケープする
    static func string(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            if let shortEscape = shortEscapes[scalar] {
                escaped += shortEscape
            } else if scalar <= lastC0Control || scalar == delete {
                escaped += unicodeEscape(scalar)
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
        return quote + escaped + quote
    }

    /// 1 行の文字列の配列（`["a", "b"]`）。空なら `[]`
    static func stringArray(_ values: [String]) -> String {
        "[" + values.map(string).joined(separator: arrayElementSeparator) + "]"
    }

    private static func unicodeEscape(_ scalar: Unicode.Scalar) -> String {
        let hexDigits = String(scalar.value, radix: hexRadix, uppercase: true)
        let padding = String(repeating: "0", count: max(0, unicodeEscapeDigitCount - hexDigits.count))
        return unicodeEscapePrefix + padding + hexDigits
    }
}
