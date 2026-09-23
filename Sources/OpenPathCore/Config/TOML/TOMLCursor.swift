/// ソース上の位置。行・列とも 1 始まりで、列は Unicode スカラー単位。
struct TOMLSourcePosition {
    let line: Int
    let column: Int
}

extension TOMLParseError {
    init(_ kind: Kind, at position: TOMLSourcePosition) {
        self.init(line: position.line, column: position.column, kind: kind)
    }
}

/// ソースを Unicode スカラー単位で読み進め、現在の行・列を追跡するカーソル。
/// Character（書記素クラスタ）単位だと引用符の直後の結合文字が引用符とまとまって区切りを見失うため、スカラー単位で扱う。
struct TOMLCursor {
    private static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"
    private static let firstLine = 1
    private static let firstColumn = 1
    private static let tab: Unicode.Scalar = "\t"
    private static let lastC0Control: Unicode.Scalar = "\u{1F}"
    private static let delete: Unicode.Scalar = "\u{7F}"

    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var line = Self.firstLine
    private var lineStartIndex = 0

    init(source: String) {
        var scalars = Array(source.unicodeScalars)
        if scalars.first == Self.byteOrderMark {
            scalars.removeFirst()
        }
        self.scalars = scalars
    }

    var isAtEnd: Bool { index >= scalars.count }

    var current: Unicode.Scalar? { scalar(at: index) }

    var position: TOMLSourcePosition {
        TOMLSourcePosition(line: line, column: index - lineStartIndex + Self.firstColumn)
    }

    /// 改行（LF または CRLF）の先頭にいるか。単独の CR は改行として扱わない
    var isAtNewline: Bool {
        current == "\n" || (current == "\r" && scalar(at: index + 1) == "\n")
    }

    var isAtLineEnd: Bool { isAtEnd || isAtNewline }

    func hasPrefix(_ prefix: String) -> Bool {
        prefix.unicodeScalars.enumerated().allSatisfy { offset, expected in
            scalar(at: index + offset) == expected
        }
    }

    mutating func advance() {
        guard let scalar = current else { return }
        index += 1
        if scalar == "\n" {
            line += 1
            lineStartIndex = index
        }
    }

    /// 改行があれば消費して true を返す
    mutating func consumeNewline() -> Bool {
        guard isAtNewline else { return false }
        if current == "\r" {
            advance()
        }
        advance()
        return true
    }

    /// TOML の空白（スペースとタブ）を読み飛ばす
    mutating func skipWhitespace() {
        while current == " " || current == Self.tab {
            advance()
        }
    }

    /// `#` から行末までのコメントを読み飛ばす。改行そのものは消費しない
    mutating func skipComment() throws(TOMLParseError) {
        guard current == "#" else { return }
        while let scalar = current, !isAtNewline {
            try rejectControlCharacter(scalar)
            advance()
        }
    }

    /// 文字列とコメントに書けない制御文字（タブ以外の C0 制御文字と DEL）を現在位置のエラーにする
    func rejectControlCharacter(_ scalar: Unicode.Scalar) throws(TOMLParseError) {
        let isForbidden = (scalar <= Self.lastC0Control && scalar != Self.tab) || scalar == Self.delete
        guard isForbidden else { return }
        throw TOMLParseError(.unexpectedCharacter(scalar), at: position)
    }

    private func scalar(at index: Int) -> Unicode.Scalar? {
        scalars.indices.contains(index) ? scalars[index] : nil
    }
}
