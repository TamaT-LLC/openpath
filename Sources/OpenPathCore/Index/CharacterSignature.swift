/// 候補に含まれる文字（正規化後の FuzzyCharacterCode）の集合を 256 ビットに畳んだもの。前置フィルタに使う（DSN-002 §5）。
///
/// ASCII は 1 文字 1 ビットで正確に表し、それ以外の文字はコードを残りの 128 ビットに畳む。
/// 畳み込みで別の文字とビットを共有することはあるが、含まれる文字のビットは必ず立つため、
/// 「クエリの文字のビットが立っていない候補はマッチしない」ことだけを判定に使えば取りこぼしは起きない。
struct CharacterSignature: Sendable {
    private static let wordBitCount = UInt32(UInt64.bitWidth)
    /// ASCII（0x00〜0x7F）に割り当てるビット数。それ以外の文字はこの後ろに畳む
    private static let asciiBitCount: UInt32 = 128
    private static let nonASCIIBitCount: UInt32 = 128

    private var bits = SIMD4<UInt64>()

    init() {}

    init(_ codes: some Sequence<FuzzyCharacterCode>) {
        for code in codes {
            insert(code)
        }
    }

    mutating func insert(_ code: FuzzyCharacterCode) {
        let value = code.rawValue
        let bit = value < Self.asciiBitCount ? value : Self.asciiBitCount + value % Self.nonASCIIBitCount
        bits[Int(bit / Self.wordBitCount)] |= 1 << UInt64(bit % Self.wordBitCount)
    }

    mutating func formUnion(_ other: CharacterSignature) {
        bits |= other.bits
    }

    /// `other` の文字（のビット）をすべて含む可能性があるか。false なら確実に含まない
    func mayContainAll(of other: CharacterSignature) -> Bool {
        bits & other.bits == other.bits
    }
}
