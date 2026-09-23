/// info 以上のメッセージに紛れ込んだパスを伏せ字にする（NFR-05 の多層防御）。
///
/// パスは `Log.debugPath` で記録する契約で、これは契約違反を拾うための安全網。
/// ファイル名には空白や記号を含められ、文中のパスがどこで終わるかは判別できないため、
/// 伏せ字の取りこぼしより過剰な伏せ字を優先する。
/// - 引用符・括弧の直後から始まるパスは、対応する閉じ記号の直前までを伏せる（空白を含んでよい）。
/// - それ以外のパスは、開始位置からメッセージの末尾までを伏せる。
///
/// パスを含まないメッセージは変更しない。相対パスやファイル名だけの文字列は検出できない。
enum PathRedactor {
    static let placeholder = "<path>"

    /// 検出対象はすべて "/" を含むため、含まないメッセージは正規表現を使わずに返す。
    private static let pathMarker: Character = "/"

    /// パスの直前にあるとき、対応する閉じ記号までをパスとみなす開き記号。
    private static let closingDelimiters: [Character: Character] = [
        "\"": "\"",
        "'": "'",
        "`": "`",
        "(": ")",
        "[": "]",
        "{": "}",
        "<": ">",
        "“": "”",
        "‘": "’",
        "「": "」",
        "『": "』",
    ]

    static func redact(_ message: String) -> String {
        guard message.contains(pathMarker) else { return message }
        // Regex は Sendable でなく static に保持できないため、呼び出しごとに生成する。
        // boundary はパスの直前の文字。英数字等に続く "/"（"and/or" や "1/2"）はパスとみなさない。
        // "//" は URL のスキーム区切り、直後が空白の "/" は記号としての斜線とみなし対象外にする。
        let pathStartPattern = #/(?<boundary>^|[^A-Za-z0-9._\-/~])(?<path>file://\S|~/\S|/[^/\s])/#

        var redacted = ""
        var remaining = message[...]
        while let match = remaining.firstMatch(of: pathStartPattern) {
            let pathStart = match.output.path.startIndex
            let pathEnd = endOfPath(in: remaining, from: pathStart, openedBy: match.output.boundary.last)
            redacted += remaining[..<pathStart]
            redacted += placeholder
            remaining = remaining[pathEnd...]
        }
        redacted += remaining
        return redacted
    }

    /// 開き記号に対応する閉じ記号の位置を返す。閉じ記号が無い場合や、開き記号が無い場合は末尾を返す。
    private static func endOfPath(
        in text: Substring,
        from pathStart: String.Index,
        openedBy openingDelimiter: Character?
    ) -> String.Index {
        guard let openingDelimiter, let closingDelimiter = closingDelimiters[openingDelimiter] else {
            return text.endIndex
        }
        var searchStart = pathStart
        while let candidate = text[searchStart...].firstIndex(of: closingDelimiter) {
            let next = text.index(after: candidate)
            // 直後に英数字が続く記号は単語の一部（"Bob's" のアポストロフィ等）とみなし、パスの終わりにしない
            guard next < text.endIndex, isASCIIAlphanumeric(text[next]) else { return candidate }
            searchStart = next
        }
        return text.endIndex
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
