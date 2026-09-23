import Foundation

/// 日本語を含むパスを検索するための正規化（DSN-002 §5、REQ-001 FR-PALETTE-06）。`FuzzyMatcher` の既定。
///
/// 元の文字列の Character（書記素クラスタ）ごとに次の順で適用し、結果の各文字にその Character のオフセットを対応づける。
/// 1. Unicode NFC に合成する。macOS のファイル名は NFD（濁点が結合文字）で保存されていることがある
/// 2. `folding(options:locale:)` で大文字小文字・幅（全角英数字、半角カナ）・ラテン文字のアクセントを同一視する
/// 3. カタカナをひらがなに寄せる。ローマ字には変換しない
///
/// 次は同一視しない。
/// - 濁点・半濁点の有無: しりょう と じりょう は別の語のため。かなを含む文字には diacriticInsensitive を適用しない
/// - 小書きのかな（ょ と よ）: IME の入力では常に区別されており、同一視すると誤マッチが増えるだけのため
/// - 長音符 ー とハイフンなどの記号
public struct JapaneseAwareNormalizer: TextNormalizer {
    private static let foldingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
    /// かなを含む文字の folding。diacriticInsensitive を外して濁点・半濁点を保つ。
    /// macOS の Foundation は全角の濁点を落とさないが、Unicode 照合（UCA）では濁点はアクセントと同じ扱いで、実装次第で落ちうる。
    /// また半角の濁点（ﾞ）は diacriticInsensitive と併用すると幅の同一視が効かず、ｶﾞ が カﾞ のまま残る
    private static let kanaFoldingOptions: String.CompareOptions = [.caseInsensitive, .widthInsensitive]
    private static let asciiUppercaseLetters = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let asciiLowercaseDistance = UInt8(ascii: "a") - UInt8(ascii: "A")
    /// CJK 統合漢字（U+4E00〜U+9FFF）。分解も大文字小文字も幅の違いも持たない
    private static let cjkUnifiedIdeographs: ClosedRange<UInt32> = 0x4E00...0x9FFF

    /// `kanaTableKey(of:)` で 1 つ目のスカラーを置くビット位置（2 つ目のスカラーは下位 32 ビット）
    private static let kanaTableKeyFirstScalarShift: UInt64 = 32

    /// かな 1 文字と、それに濁点・半濁点が付いた文字の畳み込み結果。
    /// 日本語のファイル名に頻出し、特に NFD の濁点付きのかなは 1 文字ごとに Foundation を何度も呼ぶことになるため、
    /// 初回に `foldedWithFoundation` の結果を表にしておく。
    /// 鍵はスカラーの並びそのもの（Character の hash は正準等価を扱うため遅い）なので、NFC の が と NFD の か + 濁点は別々に載せる
    private static let kanaFoldingTable: [UInt64: [Character]] = Dictionary(
        JapaneseKana.charactersWithVoicingMarks.compactMap { character in
            kanaTableKey(of: character).map { ($0, Array(foldedWithFoundation(character))) }
        },
        uniquingKeysWith: { first, _ in first }
    )

    public init() {}

    public func normalize(_ text: String) -> NormalizedText {
        var characters: [Character] = []
        var sourceOffsets: [Int] = []
        characters.reserveCapacity(text.utf8.count)
        sourceOffsets.reserveCapacity(text.utf8.count)
        for (offset, character) in text.enumerated() {
            if let folded = Self.foldedASCIIOrIdeograph(character) {
                characters.append(folded)
                sourceOffsets.append(offset)
                continue
            }
            let foldedKana = Self.kanaTableKey(of: character).flatMap { Self.kanaFoldingTable[$0] }
            // 複数文字に展開された場合（ß → ss）も、すべて同じ元の位置に対応づける
            for folded in foldedKana ?? Array(Self.foldedWithFoundation(character)) {
                characters.append(folded)
                sourceOffsets.append(offset)
            }
        }
        return NormalizedText(characters: characters, sourceOffsets: sourceOffsets)
    }

    /// 1〜2 スカラーの文字を表の鍵にする。3 スカラー以上なら nil。
    /// 2 つ目が無い場合は 0 を入れる（U+0000 は制御文字で、書記素クラスタの 2 つ目のスカラーにはならない）
    private static func kanaTableKey(of character: Character) -> UInt64? {
        var iterator = character.unicodeScalars.makeIterator()
        guard let first = iterator.next() else { return nil }
        let second = iterator.next()
        guard iterator.next() == nil else { return nil }
        return UInt64(first.value) << kanaTableKeyFirstScalarShift | UInt64(second?.value ?? 0)
    }

    /// 候補の大半を占める ASCII と CJK 統合漢字を、Foundation も表も使わずに畳み込む。該当しなければ nil。
    /// どちらも 1 スカラーで NFC 合成済みの文字に限るので、`foldedWithFoundation` と同じ結果になる
    private static func foldedASCIIOrIdeograph(_ character: Character) -> Character? {
        let scalars = character.unicodeScalars
        guard let scalar = scalars.first, scalars.dropFirst().isEmpty else { return nil }
        if scalar.isASCII {
            let ascii = UInt8(ascii: scalar)
            guard asciiUppercaseLetters.contains(ascii) else { return character }
            return Character(Unicode.Scalar(ascii + asciiLowercaseDistance))
        }
        return cjkUnifiedIdeographs.contains(scalar.value) ? character : nil
    }

    private static func foldedWithFoundation(_ character: Character) -> String {
        let composed = String(character).precomposedStringWithCanonicalMapping
        guard JapaneseKana.containsKana(composed) else {
            return composed.folding(options: foldingOptions, locale: nil).precomposedStringWithCanonicalMapping
        }
        let folded = composed.folding(options: kanaFoldingOptions, locale: nil)
        // 分解してからカタカナを置き換え、再び合成する。半角カナの ｶﾞ（幅の同一視で カ + 結合濁点 になる）も が に揃う
        return JapaneseKana.hiraganaFolded(folded.decomposedStringWithCanonicalMapping).precomposedStringWithCanonicalMapping
    }
}
