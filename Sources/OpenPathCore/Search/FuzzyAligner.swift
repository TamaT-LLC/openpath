/// クエリの各文字を対象のどの位置に一致させるかを選ぶ。
///
/// 1. 後方からの貪欲走査で、各クエリ文字を置ける最も後ろの位置（`latest`）を求める。
///    これより後ろに置くと残りのクエリ文字がマッチできなくなる上限になる。
/// 2. `latest[0]` までの 1 文字目の出現それぞれを開始位置として前方へ貪欲に位置を選び、合計スコアが最大のものを採る。
///    各文字は (直前の位置, latest] の範囲で局所的な加点（位置ボーナス + 連続 or ギャップ）が最大の位置に置く。
///
/// DP（Smith-Waterman 系）ほど厳密ではないが、同じ文字が複数回出ても区切り直後などボーナスの高い位置を拾える。
/// ホットループは for-in ではなく while で書いている。デバッグビルドでは Range の反復が特殊化されず数倍遅くなるため。
struct FuzzyAligner {
    struct Alignment {
        let score: Int
        /// 一致させた正規化後の位置（昇順）
        let indices: [Int]
    }

    private let queryCodes: [FuzzyCharacterCode]
    private let textElements: [FuzzyTargetElement]

    init(query: FuzzyQuery, target: FuzzyTarget) {
        queryCodes = query.codes
        textElements = target.elements
    }

    /// 最もスコアの高い一致位置の選び方。マッチしない場合は nil
    func bestAlignment() -> Alignment? {
        guard !queryCodes.isEmpty,
              queryCodes.count <= textElements.count,
              let latest = latestPositions()
        else {
            return nil
        }
        var best: Alignment?
        var indices: [Int] = []
        indices.reserveCapacity(queryCodes.count)
        let firstCode = queryCodes[0]
        var start = 0
        while start <= latest[0] {
            if textElements[start].code == firstCode {
                indices.removeAll(keepingCapacity: true)
                let score = greedyScore(start: start, latest: latest, recordingInto: &indices)
                // 同点なら先に始まるものを残す
                if score > best?.score ?? Int.min {
                    best = Alignment(score: score, indices: indices)
                }
            }
            start += 1
        }
        return best
    }

    /// 各クエリ文字を置ける最も後ろの位置。マッチしない場合は nil
    private func latestPositions() -> [Int]? {
        var positions = [Int](repeating: 0, count: queryCodes.count)
        var queryIndex = queryCodes.count - 1
        var textIndex = textElements.count - 1
        while queryIndex >= 0, textIndex >= 0 {
            if textElements[textIndex].code == queryCodes[queryIndex] {
                positions[queryIndex] = textIndex
                queryIndex -= 1
            }
            textIndex -= 1
        }
        return queryIndex < 0 ? positions : nil
    }

    /// `start` から前方へ貪欲に位置を選び、合計スコアを返す。選んだ位置は `indices` に追記する
    private func greedyScore(start: Int, latest: [Int], recordingInto indices: inout [Int]) -> Int {
        indices.append(start)
        var score = textElements[start].bonus
        var previous = start
        var queryIndex = 1
        while queryIndex < queryCodes.count {
            let chosen = bestNextPosition(for: queryIndex, after: previous, upTo: latest[queryIndex])
            indices.append(chosen.index)
            score += chosen.gain
            previous = chosen.index
            queryIndex += 1
        }
        return score
    }

    /// (previous, limit] の範囲で局所加点が最大の位置（同点なら手前）。
    /// `limit` は `latest` 由来で、`previous` より後ろにある一致位置であることを前提とする
    private func bestNextPosition(for queryIndex: Int, after previous: Int, upTo limit: Int) -> (index: Int, gain: Int) {
        let queryCode = queryCodes[queryIndex]
        assert(previous < limit && textElements[limit].code == queryCode, "limit が一致位置ではない")

        var index = previous + 1
        while index < limit, textElements[index].code != queryCode {
            index += 1
        }
        var chosen = (index: index, gain: FuzzyScoring.transitionGain(from: previous, to: index, bonus: textElements[index].bonus))

        // より後ろにボーナスの高い一致があれば乗り換える。ギャップが広がり上回れなくなった時点で打ち切る
        index += 1
        while index <= limit, chosen.gain < FuzzyScoring.maxGain(atGapOf: index - previous - 1) {
            let element = textElements[index]
            if element.code == queryCode {
                let gain = FuzzyScoring.transitionGain(from: previous, to: index, bonus: element.bonus)
                if gain > chosen.gain {
                    chosen = (index, gain)
                }
            }
            index += 1
        }
        return chosen
    }
}
