/// 前処理（正規化）済みのクエリ。キー入力ごとに一度作り、全候補のマッチで使い回す。
/// 作成には `FuzzyMatcher.prepareQuery(_:)` を使い、対象と同じ正規化を適用する。
public struct FuzzyQuery: Sendable {
    let codes: [FuzzyCharacterCode]

    init(normalized: NormalizedText) {
        codes = FuzzyCharacterCode.codes(of: normalized.characters)
    }
}

/// 前処理（正規化・位置ボーナス計算）済みのマッチ対象。
/// 候補インデックス構築時に一度だけ作ることで、キー入力ごとの正規化を避ける。
/// 作成には `FuzzyMatcher.prepareTarget(_:)` を使い、クエリと同じ正規化を適用する。
///
/// 候補数 × 文字数ぶん常駐するため、1 文字を 4 バイト（`FuzzyTargetElement`）に詰めて持つ。
public struct FuzzyTarget: Sendable {
    /// 正規化後の各文字のコードと、そこに一致したときの位置ボーナス
    let elements: [FuzzyTargetElement]
    /// `elements[i]` が由来する元の文字列上の Character オフセット。
    /// 正規化で文字数が変わらなかった場合（大半の候補）は i そのものなので持たない（nil）
    private let sourceOffsets: [Int]?

    init(original text: String, normalized: NormalizedText) {
        // 大文字小文字や区切りは正規化で失われうるため、ボーナスは元の文字列で判定する
        let originalBonuses = FuzzyScoring.positionalBonuses(of: Array(text))
        let sourceOffsets = normalized.sourceOffsets
        let codes = FuzzyCharacterCode.codes(of: normalized.characters)
        elements = sourceOffsets.indices.map { index in
            let offset = sourceOffsets[index]
            // 1 文字が複数文字に展開された場合、2 文字目以降は単語の途中とみなす
            let isExpandedTail = index > sourceOffsets.startIndex && sourceOffsets[index - 1] == offset
            let hasBonus = !isExpandedTail && originalBonuses.indices.contains(offset)
            return FuzzyTargetElement(code: codes[index], bonus: hasBonus ? originalBonuses[offset] : FuzzyScoring.noBonus)
        }
        self.sourceOffsets = sourceOffsets.elementsEqual(sourceOffsets.indices) ? nil : sourceOffsets
    }

    /// 正規化後の位置の列を、元の文字列上の Character オフセット（昇順・重複なし）に戻す
    func sourcePositions(of indices: [Int]) -> [Int] {
        guard let sourceOffsets else { return indices }
        var positions: [Int] = []
        positions.reserveCapacity(indices.count)
        for index in indices {
            let offset = sourceOffsets[index]
            if positions.last != offset {
                positions.append(offset)
            }
        }
        return positions
    }
}
