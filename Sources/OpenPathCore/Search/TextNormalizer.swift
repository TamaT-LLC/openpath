/// 比較用に正規化した文字列。
/// 正規化で文字が展開・削除されてもハイライト位置を元の文字列に戻せるよう、
/// 各文字が由来する元の文字列上の Character オフセットを併せて持つ。
public struct NormalizedText: Sendable, Equatable {
    /// 比較に使う文字の並び
    public let characters: [Character]
    /// `characters[i]` が由来する元の文字列上の Character オフセット。
    /// 昇順で、1 文字が複数文字に展開された場合は同じ値が連続する。
    public let sourceOffsets: [Int]

    public init(characters: [Character], sourceOffsets: [Int]) {
        precondition(characters.count == sourceOffsets.count, "characters と sourceOffsets の要素数が一致しない")
        precondition(zip(sourceOffsets, sourceOffsets.dropFirst()).allSatisfy { $0 <= $1 }, "sourceOffsets が昇順でない")
        self.characters = characters
        self.sourceOffsets = sourceOffsets
    }
}

/// マッチの前にクエリと対象文字列の両方へ同じ規則で適用する正規化。
/// 日本語の同一視（NFC・全半角・かな）を行う既定の実装は `JapaneseAwareNormalizer`。
public protocol TextNormalizer: Sendable {
    func normalize(_ text: String) -> NormalizedText
}

/// 大文字小文字の同一視だけを行う正規化
public struct LowercaseNormalizer: TextNormalizer {
    public init() {}

    public func normalize(_ text: String) -> NormalizedText {
        var characters: [Character] = []
        var sourceOffsets: [Int] = []
        characters.reserveCapacity(text.utf8.count)
        sourceOffsets.reserveCapacity(text.utf8.count)
        for (offset, character) in text.enumerated() {
            // 小文字化で複数文字になる場合も、すべて同じ元の位置に対応づける
            for lowercased in character.lowercased() {
                characters.append(lowercased)
                sourceOffsets.append(offset)
            }
        }
        return NormalizedText(characters: characters, sourceOffsets: sourceOffsets)
    }
}
