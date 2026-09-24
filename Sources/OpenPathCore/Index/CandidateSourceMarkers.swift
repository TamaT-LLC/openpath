/// 再構築 1 回で収集するソース 1 つと、その扱い。
struct CandidateSourceRefresh: Sendable {
    let source: any CandidateSource
    /// 前回の収集の記録。あれば先に変更の有無を確かめ、変わっていなければ収集しない（周期の再構築のみ。Issue #78）
    let marker: (any Sendable)?
}

/// ソースごとの、直近の収集で受け取った変更の検知の記録（Issue #78）。
///
/// CandidateIndexRebuilder が MainActor 上で持ち、再構築 1 回で収集するソースを決めるのと、
/// 再構築の結果を反映するのに使う。記録があるのは、直近の収集の結果がインデックスにあるソースだけにする。
struct CandidateSourceMarkers {
    private var markers: [CandidateSourceKind: any Sendable] = [:]

    /// 再構築 1 回で収集するソースと、変わっていなければ収集を省くために渡す記録。
    ///
    /// - 全件（起動時・手動・設定の変更）: 記録にかかわらず全ソースを収集する（FR-CONFIG-02）
    /// - 周期: 記録のある ChangeTrackingCandidateSource には記録を渡し、変更の有無を確かめさせる。それ以外は収集する
    /// - 履歴だけ: 履歴を収集する
    func refreshes(for scope: CandidateRebuildScope, sources: [any CandidateSource]) -> [CandidateSourceRefresh] {
        switch scope {
        case .all:
            sources.map { CandidateSourceRefresh(source: $0, marker: nil) }
        case .periodic:
            sources.map { source in
                let marker = source is any ChangeTrackingCandidateSource ? markers[source.kind] : nil
                return CandidateSourceRefresh(source: source, marker: marker)
            }
        case .history:
            sources.filter { $0.kind == .history }.map { CandidateSourceRefresh(source: $0, marker: nil) }
        }
    }

    /// 再構築の結果を反映する。収集したソースは新しい記録に置き換え（記録が無ければ消す）、変わっていなかったソースは残す。
    /// 取り消し・失敗・除去したソースは、インデックスの候補が記録と対応しなくなりうるため消し、次は収集させる。
    mutating func update(with outcome: CandidateRebuildOutcome) {
        for kind in outcome.replaced.keys {
            markers[kind] = outcome.markers[kind]
        }
        for kind in outcome.cancelled.union(outcome.failed.keys).union(outcome.removed) {
            markers[kind] = nil
        }
    }

    /// すべての記録を消す。候補ソースに関わる設定が変わり、同じソースでも走査の条件が変わったときに呼ぶ
    mutating func removeAll() {
        markers.removeAll()
    }
}
