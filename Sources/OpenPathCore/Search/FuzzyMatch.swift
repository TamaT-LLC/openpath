/// ファジーマッチの結果
public struct FuzzyMatch: Sendable, Equatable {
    /// 大きいほど良い一致。マッチした場合は常に 1 以上（frecency との乗算で順位が反転しないように）
    public let score: Int
    /// 一致した文字の、元の文字列における Character オフセット（昇順・重複なし）。UI のハイライトに使う
    public let positions: [Int]

    public init(score: Int, positions: [Int]) {
        self.score = score
        self.positions = positions
    }
}

/// 候補のどの文字列にマッチしたか
public enum FuzzyMatchField: Sendable, Equatable {
    case name
    case path
}

/// 候補の name / path のうち、スコアの高い方のマッチ結果
public struct FuzzyCandidateMatch: Sendable, Equatable {
    /// name にマッチした場合はボーナス適用後のスコア
    public let score: Int
    public let field: FuzzyMatchField
    /// `field` 側の文字列における Character オフセット
    public let positions: [Int]

    public init(score: Int, field: FuzzyMatchField, positions: [Int]) {
        self.score = score
        self.field = field
        self.positions = positions
    }
}
