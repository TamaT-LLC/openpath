extension CandidateSourceKind {
    /// 統合時の優先度の段（DSN-002 §3「history > ghq > roots」）。宣言順に優先する
    private enum MergeTier: Int, Comparable {
        case history
        case ghq
        case root

        static func < (lhs: MergeTier, rhs: MergeTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private var mergeTier: MergeTier {
        switch self {
        case .history: .history
        case .ghq: .ghq
        case .root: .root
        }
    }

    /// 同じパスが複数のソースにあるとき、`lhs` を `rhs` より優先するか。
    /// roots 同士（入れ子のルート）は差し替えの順序に依らないよう、ルートの文字列の昇順で決める。
    static func mergesBefore(_ lhs: CandidateSourceKind, _ rhs: CandidateSourceKind) -> Bool {
        if lhs.mergeTier != rhs.mergeTier {
            return lhs.mergeTier < rhs.mergeTier
        }
        guard case .root(let lhsRoot) = lhs, case .root(let rhsRoot) = rhs else {
            return false
        }
        return lhsRoot < rhsRoot
    }
}
