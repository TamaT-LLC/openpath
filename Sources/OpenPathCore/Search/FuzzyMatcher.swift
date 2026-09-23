/// 先頭一致・区切り直後・CamelCase 境界・連続一致にボーナスを付ける貪欲なファジーマッチ（fzf v2 の簡略版）。
/// スコア規則は `FuzzyScoring`、一致位置の選び方は `FuzzyAligner` を参照。
///
/// 正規化（大文字小文字・日本語の同一視など）は `TextNormalizer` として差し込む。既定は `JapaneseAwareNormalizer`。
/// 候補側は `prepareTarget(_:)` で前処理した結果を保持しておき、キー入力ごとに `prepareQuery(_:)` だけを行う使い方を想定する。
public struct FuzzyMatcher: Sendable {
    private let normalizer: any TextNormalizer

    public init(normalizer: any TextNormalizer = JapaneseAwareNormalizer()) {
        self.normalizer = normalizer
    }

    public func prepareQuery(_ query: String) -> FuzzyQuery {
        FuzzyQuery(normalized: normalizer.normalize(query))
    }

    public func prepareTarget(_ text: String) -> FuzzyTarget {
        FuzzyTarget(original: text, normalized: normalizer.normalize(text))
    }

    /// `text` に `query` がマッチすればスコアと一致位置を返す。空クエリは常に最低スコアでマッチする
    public func score(query: String, in text: String) -> FuzzyMatch? {
        score(query: prepareQuery(query), in: prepareTarget(text))
    }

    public func score(query: FuzzyQuery, in target: FuzzyTarget) -> FuzzyMatch? {
        let queryLength = query.codes.count
        guard queryLength > 0 else {
            return FuzzyMatch(score: FuzzyScoring.minimumMatchScore, positions: [])
        }
        guard let alignment = FuzzyAligner(query: query, target: target).bestAlignment() else {
            return nil
        }
        let isExactMatch = queryLength == target.elements.count
        let score = alignment.score + (isExactMatch ? FuzzyScoring.exactMatchBonus : 0)
        return FuzzyMatch(
            score: max(score, FuzzyScoring.minimumMatchScore),
            positions: target.sourcePositions(of: alignment.indices)
        )
    }

    /// 候補の `name` と `path` の両方にマッチさせ、高い方を返す（`name` には +20%、同点なら `name`）
    public func scoreCandidate(query: String, name: String, path: String) -> FuzzyCandidateMatch? {
        scoreCandidate(query: prepareQuery(query), name: prepareTarget(name), path: prepareTarget(path))
    }

    public func scoreCandidate(query: FuzzyQuery, name: FuzzyTarget, path: FuzzyTarget) -> FuzzyCandidateMatch? {
        let nameMatch = score(query: query, in: name).map {
            FuzzyCandidateMatch(score: FuzzyScoring.applyingNameBonus(to: $0.score), field: .name, positions: $0.positions)
        }
        let pathMatch = score(query: query, in: path).map {
            FuzzyCandidateMatch(score: $0.score, field: .path, positions: $0.positions)
        }
        guard let nameMatch else { return pathMatch }
        guard let pathMatch else { return nameMatch }
        return nameMatch.score >= pathMatch.score ? nameMatch : pathMatch
    }
}
