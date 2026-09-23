/// 前処理（正規化）済みのクエリ。キー入力ごとに一度作り、全候補のマッチで使い回す。
/// 作成には `FuzzyMatcher.prepareQuery(_:)` を使い、対象と同じ正規化を適用する。
public struct FuzzyQuery: Sendable {
    let characters: [Character]

    init(normalized: NormalizedText) {
        characters = normalized.characters
    }
}

/// 前処理（正規化・位置ボーナス計算）済みのマッチ対象。
/// 候補インデックス構築時に一度だけ作ることで、キー入力ごとの正規化を避ける。
/// 作成には `FuzzyMatcher.prepareTarget(_:)` を使い、クエリと同じ正規化を適用する。
public struct FuzzyTarget: Sendable {
    let characters: [Character]
    let sourceOffsets: [Int]
    /// `characters[i]` に一致したときの位置ボーナス
    let bonuses: [Int]

    init(original text: String, normalized: NormalizedText) {
        // 大文字小文字や区切りは正規化で失われうるため、ボーナスは元の文字列で判定する
        let originalBonuses = FuzzyScoring.positionalBonuses(of: Array(text))
        let sourceOffsets = normalized.sourceOffsets
        characters = normalized.characters
        self.sourceOffsets = sourceOffsets
        bonuses = sourceOffsets.indices.map { index in
            let offset = sourceOffsets[index]
            // 1 文字が複数文字に展開された場合、2 文字目以降は単語の途中とみなす
            let isExpandedTail = index > sourceOffsets.startIndex && sourceOffsets[index - 1] == offset
            guard !isExpandedTail, originalBonuses.indices.contains(offset) else { return FuzzyScoring.noBonus }
            return originalBonuses[offset]
        }
    }

    /// 正規化後の位置の列を、元の文字列上の Character オフセット（昇順・重複なし）に戻す
    func sourcePositions(of indices: [Int]) -> [Int] {
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
