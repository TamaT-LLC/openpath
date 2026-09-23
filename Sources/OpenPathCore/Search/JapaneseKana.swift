/// かなの判定とカタカナ → ひらがなの変換（`JapaneseAwareNormalizer` の部品）。
/// コードポイントは Unicode のブロック表に基づく。
enum JapaneseKana {
    /// ァ（U+30A1）〜ヶ（U+30F6）。ひらがな ぁ（U+3041）〜ゖ（U+3096）と同じ並び
    private static let katakanaLetters: ClosedRange<UInt32> = 0x30A1...0x30F6
    /// ヽ（U+30FD）ヾ（U+30FE）。ひらがなの ゝ ゞ と同じ並び
    private static let katakanaIterationMarks: ClosedRange<UInt32> = 0x30FD...0x30FE
    /// カタカナとひらがなのコードポイントの差（ア U+30A2 − あ U+3042）
    private static let katakanaToHiraganaDistance: UInt32 = 0x60

    /// かなのブロック: ひらがな（結合濁点 U+3099・結合半濁点 U+309A を含む）、カタカナ、カタカナ拡張、半角カナ
    private static let kanaBlocks: [ClosedRange<UInt32>] = [
        0x3040...0x309F,
        0x30A0...0x30FF,
        0x31F0...0x31FF,
        0xFF65...0xFF9F,
    ]

    /// 全角のかな: ぁ〜ゖ、ゝ ゞ、ァ〜ヺ、ー ヽ ヾ
    private static let fullwidthKanaLetters: [ClosedRange<UInt32>] = [
        0x3041...0x3096,
        0x309D...0x309E,
        0x30A1...0x30FA,
        0x30FC...0x30FE,
    ]
    /// 結合濁点（U+3099）・結合半濁点（U+309A）。NFD では濁点・半濁点がこの形で直前のかなに付く
    private static let combiningVoicingMarks: [UInt32] = [0x3099, 0x309A]
    /// 半角カナ ｦ（U+FF66）〜ﾝ（U+FF9D）。半角の長音符 ｰ を含む
    private static let halfwidthKanaLetters: ClosedRange<UInt32> = 0xFF66...0xFF9D
    /// 半角の濁点 ﾞ（U+FF9E）・半濁点 ﾟ（U+FF9F）
    private static let halfwidthVoicingMarks: [UInt32] = [0xFF9E, 0xFF9F]

    /// かな 1 文字と、それに濁点・半濁点が付いた文字（NFD の が、半角の ｶﾞ など）。
    /// 濁点・半濁点と合成できないかなとの組み合わせ（あ + 濁点）も含む
    static var charactersWithVoicingMarks: [Character] {
        let fullwidth = fullwidthKanaLetters.joined().flatMap { characters(base: $0, marks: combiningVoicingMarks) }
        let halfwidth = halfwidthKanaLetters.flatMap { characters(base: $0, marks: halfwidthVoicingMarks) }
        return fullwidth + halfwidth
    }

    static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            kanaBlocks.contains { $0.contains(scalar.value) }
        }
    }

    /// 文字列中のカタカナをひらがなに置き換える。
    /// 合成済みのひらがなが無い ヷ〜ヺ（U+30F7〜U+30FA）は、分解（NFD）してから渡せば わ + 結合濁点 などになる
    static func hiraganaFolded(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(hiragana(for: scalar) ?? scalar)
        }
        return String(scalars)
    }

    /// カタカナに対応するひらがな。カタカナでないか、対応するひらがなが無ければ nil
    private static func hiragana(for scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let value = scalar.value
        guard katakanaLetters.contains(value) || katakanaIterationMarks.contains(value) else { return nil }
        return Unicode.Scalar(value - katakanaToHiraganaDistance)
    }

    /// `base` 単独と、`base` に `marks` の各文字を付けた文字
    private static func characters(base: UInt32, marks: [UInt32]) -> [Character] {
        guard let baseScalar = Unicode.Scalar(base) else { return [] }
        let voiced = marks.compactMap(Unicode.Scalar.init).compactMap { mark -> Character? in
            var scalars = String.UnicodeScalarView()
            scalars.append(baseScalar)
            scalars.append(mark)
            // 濁点・半濁点は直前の文字と 1 つの書記素クラスタになる（1 文字にならない組み合わせは除く）
            let text = String(scalars)
            return text.count == 1 ? text.first : nil
        }
        return [Character(baseScalar)] + voiced
    }
}
