/// info 以上のメッセージに紛れ込んだパスを伏せ字にする（NFR-05 の多層防御）。
///
/// パスは本来 `Log.debugPath` で記録する。これは誤って info 以上に書かれたパスを拾うための
/// ヒューリスティックで、空白を含むパスの 2 語目以降や相対パスは検出できない。
enum PathRedactor {
    static let placeholder = "<path>"

    /// 検出対象はすべて "/" を含むため、含まないメッセージは正規表現を使わずに返す。
    private static let pathMarker: Character = "/"

    static func redact(_ message: String) -> String {
        guard message.contains(pathMarker) else { return message }
        // Regex は Sendable でなく static に保持できないため、呼び出しごとに生成する。
        // 1 つ目のグループはパスの直前の区切り文字。英数字等に続く "/"（"and/or" や "1/2"）はパスとみなさない。
        // "//" で始まるものは URL のスキーム区切りとみなし対象外にする。
        let pathPattern = #/(^|[^A-Za-z0-9._\-/~])(?:file://|~/|/(?!/))[^\s"'`)\]}>,]+/#
        return message.replacing(pathPattern) { match in
            "\(match.output.1)\(placeholder)"
        }
    }
}
