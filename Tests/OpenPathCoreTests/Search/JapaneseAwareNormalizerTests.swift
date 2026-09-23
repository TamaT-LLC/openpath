import Foundation
import Testing

import OpenPathCore

@Suite("JapaneseAwareNormalizer（日本語を含む文字列の正規化）")
struct JapaneseAwareNormalizerTests {
    /// カタカナとひらがなのコードポイントの差（ア U+30A2 − あ U+3042）
    private static let katakanaToHiraganaDistance: UInt32 = 0x60
    /// ァ（U+30A1）〜ヶ（U+30F6）。ひらがな ぁ（U+3041）〜ゖ（U+3096）と同じ並び
    private static let katakanaLetters: ClosedRange<UInt32> = 0x30A1...0x30F6
    /// 全角のかな: ぁ〜ゖ、ゝ ゞ、ァ〜ヺ、ー ヽ ヾ
    private static let fullwidthKanaLetters: [ClosedRange<UInt32>] = [
        0x3041...0x3096, 0x309D...0x309E, 0x30A1...0x30FA, 0x30FC...0x30FE,
    ]
    /// 半角カナ ｦ（U+FF66）〜ﾝ（U+FF9D）
    private static let halfwidthKatakanaLetters: ClosedRange<UInt32> = 0xFF66...0xFF9D
    private static let combiningVoicedSoundMark: UInt32 = 0x3099
    private static let combiningSemiVoicedSoundMark: UInt32 = 0x309A
    private static let halfwidthVoicedSoundMark: UInt32 = 0xFF9E
    private static let halfwidthSemiVoicedSoundMark: UInt32 = 0xFF9F
    /// 印字可能な ASCII（空白〜チルダ）
    private static let printableASCII: ClosedRange<UInt8> = 0x20...0x7E

    private let normalizer = JapaneseAwareNormalizer()

    /// 比較用の文字列をスカラー値の列で取り出す。String の == は正準等価を同一視するため、NFC かどうかはスカラーで確かめる
    private func scalarValues(_ text: String) -> [UInt32] {
        String(normalizer.normalize(text).characters).unicodeScalars.map(\.value)
    }

    private static func scalarValues(of text: String) -> [UInt32] {
        text.unicodeScalars.map(\.value)
    }

    private static func string(_ value: UInt32) throws -> String {
        String(try #require(Unicode.Scalar(value)))
    }

    // MARK: - Unicode 正規化（NFC / NFD）

    @Test("NFD で保存された濁点・半濁点付きのかなは、合成済み（NFC）の 1 文字として比較する", arguments: [
        "データ", "ガイド", "パスポート", "ビジネス資料", "ヴァイオリン",
    ])
    func decomposedKanaIsComposed(text: String) {
        let decomposed = text.decomposedStringWithCanonicalMapping
        // 前提: 濁点が結合文字に分解され、スカラー数だけが増えている
        #expect(decomposed.unicodeScalars.count > text.unicodeScalars.count)
        #expect(decomposed.count == text.count)

        let normalized = normalizer.normalize(decomposed)
        let normalizedScalars = scalarValues(decomposed)

        #expect(normalized.sourceOffsets == Array(0..<text.count))
        #expect(normalizedScalars == scalarValues(text))
        // 比較用の文字は合成済み（NFC）で持つ
        #expect(normalizedScalars == Self.scalarValues(of: String(normalized.characters).precomposedStringWithCanonicalMapping))
    }

    @Test("全角のかな + 濁点・半濁点は、NFD（結合文字）でも NFC（合成済み）でも同じ NFC の結果になる（全組み合わせ）")
    func everyVoicedKanaIsSameInNfcAndNfd() throws {
        let marks = [Self.combiningVoicedSoundMark, Self.combiningSemiVoicedSoundMark]
        for base in Self.fullwidthKanaLetters.joined() {
            for mark in marks {
                let decomposed = try Self.string(base) + Self.string(mark)
                let composed = decomposed.precomposedStringWithCanonicalMapping
                let normalized = String(normalizer.normalize(decomposed).characters)

                #expect(scalarValues(decomposed) == scalarValues(composed), "\(decomposed)")
                #expect(
                    Self.scalarValues(of: normalized) == Self.scalarValues(of: normalized.precomposedStringWithCanonicalMapping),
                    "\(decomposed)"
                )
            }
        }
    }

    @Test("NFD の濁点付きカタカナは合成済みのひらがなになる")
    func decomposedKatakanaBecomesComposedHiragana() {
        #expect(scalarValues("データ".decomposedStringWithCanonicalMapping) == Self.scalarValues(of: "でーた"))
        #expect(scalarValues("パス".decomposedStringWithCanonicalMapping) == Self.scalarValues(of: "ぱす"))
    }

    // MARK: - ひらがな / カタカナ

    @Test("カタカナはひらがなとして比較する")
    func katakanaIsFoldedToHiragana() {
        let normalized = normalizer.normalize("シリョウ")

        #expect(String(normalized.characters) == "しりょう")
        #expect(normalized.sourceOffsets == [0, 1, 2, 3])
    }

    @Test("カタカナ ァ〜ヶ はすべて対応するひらがな ぁ〜ゖ になる（NFC / NFD とも）")
    func everyKatakanaLetterMapsToHiragana() throws {
        for value in Self.katakanaLetters {
            let katakana = try Self.string(value)
            let expected = [value - Self.katakanaToHiraganaDistance]

            #expect(scalarValues(katakana) == expected, "\(katakana)")
            #expect(scalarValues(katakana.decomposedStringWithCanonicalMapping) == expected, "\(katakana) (NFD)")
        }
    }

    @Test("ひらがなはそのまま")
    func hiraganaIsUnchanged() {
        #expect(String(normalizer.normalize("しりょう").characters) == "しりょう")
    }

    @Test("繰り返し記号 ヽ ヾ は ゝ ゞ になる")
    func katakanaIterationMarksAreFolded() {
        #expect(scalarValues("ヽヾ") == Self.scalarValues(of: "ゝゞ"))
    }

    @Test("合成済みのひらがなが無い ヷ ヸ ヹ ヺ は、ひらがな + 結合濁点として比較する", arguments: [
        ("ヷ", "わ\u{3099}"), ("ヸ", "ゐ\u{3099}"), ("ヹ", "ゑ\u{3099}"), ("ヺ", "を\u{3099}"),
    ])
    func katakanaWithoutComposedHiraganaIsDecomposed(katakana: String, expected: String) {
        let normalized = normalizer.normalize(katakana)

        #expect(scalarValues(katakana) == Self.scalarValues(of: expected))
        #expect(normalized.sourceOffsets == [0])
    }

    @Test("長音符 ー はそのまま比較する（ひらがな中の ー とも一致する）")
    func prolongedSoundMarkIsKept() {
        #expect(String(normalizer.normalize("ラーメン").characters) == "らーめん")
        #expect(normalizer.normalize("ラーメン") == normalizer.normalize("らーめん"))
        #expect(normalizer.normalize("ラーメン") != normalizer.normalize("ラ-メン"))
    }

    @Test("小書きのかなは通常のかなと区別する", arguments: [("ョ", "ょ", "よ"), ("ッ", "っ", "つ"), ("ァ", "ぁ", "あ")])
    func smallKanaIsDistinguished(katakana: String, smallHiragana: String, largeHiragana: String) {
        #expect(normalizer.normalize(katakana) == normalizer.normalize(smallHiragana))
        #expect(normalizer.normalize(katakana) != normalizer.normalize(largeHiragana))
    }

    @Test("濁点・半濁点の有無は区別する", arguments: [
        ("じ", "し"), ("ば", "は"), ("ぱ", "は"), ("ぱ", "ば"), ("ジ", "シ"), ("ゔ", "う"), ("ｼﾞ", "ｼ"),
    ])
    func voicedSoundMarksAreKept(voiced: String, plain: String) {
        #expect(normalizer.normalize(voiced) != normalizer.normalize(plain))
        #expect(normalizer.normalize(voiced.decomposedStringWithCanonicalMapping) != normalizer.normalize(plain))
    }

    // MARK: - 幅

    @Test("全角の英数字・記号は半角として比較する")
    func fullwidthASCIIIsFolded() {
        let normalized = normalizer.normalize("ＡＢＣ１２３／＿")

        #expect(String(normalized.characters) == "abc123/_")
        #expect(normalized.sourceOffsets == Array(0..<8))
    }

    @Test("半角カナは全角のひらがなとして比較する")
    func halfwidthKatakanaIsFolded() {
        let normalized = normalizer.normalize("ｼﾘｮｳ")

        #expect(String(normalized.characters) == "しりょう")
        #expect(normalized.sourceOffsets == [0, 1, 2, 3])
    }

    @Test("半角カナの濁点・半濁点（ﾞ ﾟ）は直前のかなと合成した 1 文字として比較する")
    func halfwidthVoicedSoundMarksAreComposed() {
        // 半角の濁点は直前のかなと同じ Character（書記素クラスタ）になる
        #expect("ｶﾞｲﾄﾞ".count == 3)

        let normalized = normalizer.normalize("ｶﾞｲﾄﾞ")

        #expect(scalarValues("ｶﾞｲﾄﾞ") == Self.scalarValues(of: "がいど"))
        #expect(normalized.sourceOffsets == [0, 1, 2])
        #expect(scalarValues("ﾊﾟｽ") == Self.scalarValues(of: "ぱす"))
        #expect(scalarValues("ｳﾞ") == Self.scalarValues(of: "ゔ"))
    }

    @Test("半角カナ ｦ〜ﾝ はすべて対応する全角カナと同じになる")
    func everyHalfwidthKatakanaMatchesFullwidth() throws {
        for value in Self.halfwidthKatakanaLetters {
            let halfwidth = try Self.string(value)
            // 期待値は Foundation の全角化（ICU）で独立に求める
            let fullwidth = try #require(halfwidth.applyingTransform(.fullwidthToHalfwidth, reverse: true))

            #expect(normalizer.normalize(halfwidth) == normalizer.normalize(fullwidth), "\(halfwidth) / \(fullwidth)")
        }
    }

    @Test("半角カナ + ﾞ ﾟ は、全角カナ + 結合濁点・半濁点と同じ結果になる（全組み合わせ）")
    func everyHalfwidthVoicedKanaMatchesFullwidth() throws {
        let marks = [
            (halfwidth: Self.halfwidthVoicedSoundMark, combining: Self.combiningVoicedSoundMark),
            (halfwidth: Self.halfwidthSemiVoicedSoundMark, combining: Self.combiningSemiVoicedSoundMark),
        ]
        for base in Self.halfwidthKatakanaLetters {
            let halfwidthBase = try Self.string(base)
            let fullwidthBase = try #require(halfwidthBase.applyingTransform(.fullwidthToHalfwidth, reverse: true))
            for mark in marks {
                let halfwidth = try halfwidthBase + Self.string(mark.halfwidth)
                let fullwidth = try fullwidthBase + Self.string(mark.combining)

                #expect(scalarValues(halfwidth) == scalarValues(fullwidth), "\(halfwidth) / \(fullwidth)")
            }
        }
    }

    @Test("半角の長音符 ｰ は全角の ー になる")
    func halfwidthProlongedSoundMarkIsFolded() {
        #expect(scalarValues("ｰ") == Self.scalarValues(of: "ー"))
    }

    // MARK: - 大文字小文字・ラテン文字のダイアクリティカルマーク

    @Test("大文字小文字を区別しない")
    func caseIsFolded() {
        #expect(String(normalizer.normalize("FooBAR").characters) == "foobar")
        #expect(String(normalizer.normalize("ÀÉÎ").characters) == "aei")
    }

    @Test("印字可能な ASCII は小文字化だけを行い、1 文字ずつ元の位置に対応する")
    func printableASCIIIsOnlyLowercased() {
        let ascii = String(decoding: Array(Self.printableASCII), as: UTF8.self)

        let normalized = normalizer.normalize(ascii)

        #expect(String(normalized.characters) == ascii.lowercased())
        #expect(normalized.sourceOffsets == Array(0..<ascii.count))
    }

    @Test("ラテン文字のアクセントは落とす（NFC / NFD とも）", arguments: [
        ("Café", "cafe"),
        ("cafe\u{301}", "cafe"),
        ("Ñandú", "nandu"),
        ("Ångström", "angstrom"),
    ])
    func latinDiacriticsAreRemoved(text: String, expected: String) {
        let normalized = normalizer.normalize(text)

        #expect(Self.scalarValues(of: String(normalized.characters)) == Self.scalarValues(of: expected))
        #expect(normalized.sourceOffsets == Array(0..<text.count))
    }

    @Test("1 文字が複数文字に展開される場合は、同じ元の位置が続く")
    func expandedCharactersShareSourceOffset() {
        let normalized = normalizer.normalize("Straße")

        #expect(String(normalized.characters) == "strasse")
        #expect(normalized.sourceOffsets == [0, 1, 2, 3, 4, 4, 5])
    }

    @Test("漢字・絵文字はそのまま、元の Character 単位で対応する")
    func ideographsAndEmojiAreKept() {
        let normalized = normalizer.normalize("資料👨‍👩‍👧/メモ")

        #expect(String(normalized.characters) == "資料👨‍👩‍👧/めも")
        #expect(normalized.sourceOffsets == [0, 1, 2, 3, 4, 5])
    }

    @Test("空文字列は空")
    func emptyTextIsEmpty() {
        let normalized = normalizer.normalize("")

        #expect(normalized.characters.isEmpty)
        #expect(normalized.sourceOffsets.isEmpty)
    }
}
