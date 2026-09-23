/// マッチ位置をハイライトする文字列（UX-001 §3）。
///
/// 位置は `text` の Character（書記素クラスタ）単位のオフセット。FuzzyMatcher の positions と同じ単位なので、
/// 濁点が分解された NFD の日本語でも 1 文字を 1 つの位置として扱える。
public struct HighlightedText: Equatable, Sendable {
    /// ハイライトの有無が同じ文字が連続する区間。ビューはこの単位で装飾を切り替える。
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isHighlighted: Bool

        public init(text: String, isHighlighted: Bool) {
            self.text = text
            self.isHighlighted = isHighlighted
        }
    }

    public let text: String
    /// ハイライトする Character オフセット。昇順・重複なしで、`text` の範囲内のものだけを持つ。
    public let highlightedOffsets: [Int]

    /// - Parameter highlightedOffsets: 順不同・重複・範囲外を含んでよい。範囲外は捨てる。
    public init(_ text: String, highlightedOffsets: [Int] = []) {
        let validRange = 0..<text.count
        self.text = text
        self.highlightedOffsets = Set(highlightedOffsets.filter(validRange.contains)).sorted()
    }

    public var segments: [Segment] {
        let characters = Array(text)
        let highlighted = Set(highlightedOffsets)
        var segments: [Segment] = []
        var runStart = 0
        for offset in characters.indices.dropFirst()
        where highlighted.contains(offset) != highlighted.contains(runStart) {
            segments.append(Segment(text: String(characters[runStart..<offset]), isHighlighted: highlighted.contains(runStart)))
            runStart = offset
        }
        if !characters.isEmpty {
            segments.append(Segment(text: String(characters[runStart...]), isHighlighted: highlighted.contains(runStart)))
        }
        return segments
    }
}

extension HighlightedText {
    /// Character オフセットの範囲 `range` を切り出す。ハイライト位置も切り出した先頭からのオフセットに直す。
    func slice(_ range: Range<Int>) -> HighlightedText {
        let characters = Array(text)
        return HighlightedText(
            String(characters[range]),
            highlightedOffsets: highlightedOffsets.filter(range.contains).map { $0 - range.lowerBound }
        )
    }

    /// Character オフセットの範囲 `range` を 1 文字 `replacement` に置き換える。
    ///
    /// 置き換えた範囲にハイライトがあれば `replacement` をハイライトする。
    /// 省略や短縮で見えなくなった部分にもマッチがあったことを示すため。
    func replacingCharacters(in range: Range<Int>, with replacement: Character) -> HighlightedText {
        let characters = Array(text)
        let replacedText = String(characters[..<range.lowerBound]) + String(replacement)
            + String(characters[range.upperBound...])
        let shift = range.count - 1
        let offsets = highlightedOffsets.map { offset in
            if offset < range.lowerBound { return offset }
            if range.contains(offset) { return range.lowerBound }
            return offset - shift
        }
        return HighlightedText(replacedText, highlightedOffsets: offsets)
    }
}
