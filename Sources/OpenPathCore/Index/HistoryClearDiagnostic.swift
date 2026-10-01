/// 履歴のクリアで、履歴の候補をインデックスから取り除いてクエリに反映したことの診断（Issue #92）。debug ログに出す。
///
/// 実機 QA（MENU-04・MENU-05）で、取り除いた時刻（ログのタイムスタンプ）・件数・全件の再構築の途中だったかを、
/// ログの行で判定するためのもの。表示中のパレットの引き直しは `palette candidates changed` / `palette rows refreshed` で分かる。
/// パスは持たない。
public struct HistoryClearDiagnostic: Equatable, Sendable {
    /// 取り除いた履歴の候補の数
    public let removedCount: Int
    /// クリアを受けてから、取り除いた候補をクエリに反映し終えるまでの時間
    public let elapsed: Duration
    /// クリアを受けた時点で、全件の再構築の途中だったか（`CandidateIndexRebuilder.isRebuilding`）
    public let wasRebuilding: Bool

    public init(removedCount: Int, elapsed: Duration, wasRebuilding: Bool) {
        self.removedCount = removedCount
        self.elapsed = elapsed
        self.wasRebuilding = wasRebuilding
    }

    /// debug ログの文言。例: `history clear removed (candidates: 12, elapsed: 3ms, rebuilding: true)`
    public var logMessage: String {
        "history clear removed (candidates: \(removedCount), elapsed: \(InjectionLogFormat.milliseconds(elapsed)), rebuilding: \(wasRebuilding))"
    }

    /// 既定の報告先。debug ログに出す（リリースビルドの既定の info では出さない）。
    public static func log(_ diagnostic: HistoryClearDiagnostic) {
        Log.debug(diagnostic.logMessage)
    }
}
