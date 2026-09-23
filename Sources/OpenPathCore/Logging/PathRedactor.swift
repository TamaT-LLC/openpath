/// info 以上のメッセージに紛れ込んだパスを伏せ字にする（NFR-05 の多層防御）。
///
/// パスは `Log.debugPath` で記録する契約で、これは契約違反を拾うための安全網。
/// ファイル名には空白・引用符・括弧を含めどの記号も使えるため、文中のパスがどこで終わるかは判別できない。
/// そのため、パスの開始を検出したらその位置からメッセージの末尾までを伏せる（後続の文脈は失われる）。
///
/// パスを含まないメッセージは変更しない。相対パスやファイル名だけの文字列は検出できない。
enum PathRedactor {
    static let placeholder = "<path>"

    /// 検出対象はすべて "/" を含むため、含まないメッセージは正規表現を使わずに返す。
    private static let pathMarker: Character = "/"

    static func redact(_ message: String) -> String {
        guard message.contains(pathMarker) else { return message }
        // Regex は Sendable でなく static に保持できないため、呼び出しごとに生成する。
        // 英数字等に続く "/"（"and/or" や "1/2"）はパスとみなさない。
        // "//" は URL のスキーム区切り、直後が空白の "/" は記号としての斜線とみなし対象外にする。
        let pathStartPattern = #/(?:^|[^A-Za-z0-9._\-/~])(?<path>file://\S|~/\S|/[^/\s])/#
        guard let match = message.firstMatch(of: pathStartPattern) else { return message }
        return String(message[..<match.output.path.startIndex]) + placeholder
    }
}
