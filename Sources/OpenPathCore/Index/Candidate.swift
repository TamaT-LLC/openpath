import Foundation

/// パレットに出す候補 1 件（DSN-002 §2）。`CandidateIndex.query` の結果として作る。
///
/// frecency と最終使用日時はクエリ時点の履歴（HistoryStore）の値で、候補ソースからは得られない。
public struct Candidate: Sendable, Hashable {
    /// 字句的に正規化した絶対パス（末尾の `/`・`//`・`.`・`..` を除いたもの）。同一パスの統合キーでもある
    public let path: String
    /// 表示名（パスの末尾要素。ルートは "/"）
    public let name: String
    /// パネルでディレクトリとして移動できるか。ソースによって食い違った場合は false
    public let isDirectory: Bool
    /// 同じパスを持つソースのうち、優先度（history > ghq > roots）が最も高いもの
    public let source: CandidateSourceKind
    /// 履歴の frecency。履歴にない候補は 0
    public let frecency: Double
    /// 最終使用日時。履歴にない候補は nil
    public let lastUsed: Date?

    public init(path: String, name: String, isDirectory: Bool, source: CandidateSourceKind, frecency: Double, lastUsed: Date?) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.source = source
        self.frecency = frecency
        self.lastUsed = lastUsed
    }
}

/// クエリの結果 1 件。候補と、順位付けに使ったマッチ結果・総合スコアの組。
public struct RankedCandidate: Sendable, Equatable {
    public let candidate: Candidate
    /// ファジーマッチの結果。空クエリではマッチを行わないため nil
    public let match: FuzzyCandidateMatch?
    /// 総合スコア `fuzzyScore × (1 + log1p(frecency))`。空クエリでは frecency そのもの
    public let score: Double

    public init(candidate: Candidate, match: FuzzyCandidateMatch?, score: Double) {
        self.candidate = candidate
        self.match = match
        self.score = score
    }

    /// パレットの行。マッチした文字をハイライトする
    public var paletteRow: PaletteRow {
        PaletteRow(candidate: candidate, match: match)
    }
}
