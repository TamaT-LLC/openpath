/// 表示幅に収まるよう文字列を複数行に分ける。
///
/// メニュー項目の表題は折り返されず、長い説明（設定ファイルのパスを含むエラー等）でメニューが横に広がりすぎるため、
/// 通知の説明を自前で改行する。幅の測り方（フォント）は Mac 層から渡す。
/// 空白があれば最後の空白で折り返し、無ければ幅を超える直前の文字で区切る（日本語は文字間で折り返せるため）。
public enum TextLineWrapper {
    private static let newline: Character = "\n"

    /// - Parameters:
    ///   - maxWidth: 1 行の最大幅。1 文字で超える場合もその文字だけで 1 行にして先へ進む
    ///   - width: 文字列の表示幅
    /// - Returns: 各行。行頭・行末の空白は取り除く。元の改行は保つが、空の行は作らない
    public static func wrap(_ text: String, maxWidth: Double, width: (String) -> Double) -> [String] {
        text.split(separator: newline).flatMap { paragraph in
            wrapParagraph(String(paragraph), maxWidth: maxWidth, width: width)
        }
    }

    private static func wrapParagraph(_ paragraph: String, maxWidth: Double, width: (String) -> Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in paragraph {
            if current.isEmpty, character.isWhitespace {
                continue
            }
            let candidate = current + String(character)
            if current.isEmpty || width(candidate) <= maxWidth {
                current = candidate
                continue
            }
            if character.isWhitespace {
                lines.append(trimmingTrailingWhitespace(current))
                current = ""
                continue
            }
            guard let (head, tail) = splitAtLastWhitespace(current) else {
                lines.append(current)
                current = String(character)
                continue
            }
            lines.append(head)
            let rest = tail + String(character)
            if tail.isEmpty || width(rest) <= maxWidth {
                current = rest
            } else {
                lines.append(tail)
                current = String(character)
            }
        }
        let last = trimmingTrailingWhitespace(current)
        if !last.isEmpty {
            lines.append(last)
        }
        return lines
    }

    /// 最後の空白の前後に分ける。空白の前が空になる（行頭の空白しかない）場合は nil
    private static func splitAtLastWhitespace(_ text: String) -> (head: String, tail: String)? {
        guard let space = text.lastIndex(where: \.isWhitespace) else { return nil }
        let head = trimmingTrailingWhitespace(String(text[..<space]))
        guard !head.isEmpty else { return nil }
        return (head, String(text[text.index(after: space)...]))
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var trimmed = Substring(text)
        while let last = trimmed.last, last.isWhitespace {
            trimmed.removeLast()
        }
        return String(trimmed)
    }
}
