/// 再構築 1 回分の対象。
enum CandidateRebuildScope: Sendable, Equatable {
    /// 全ソースを必ず収集し直す（起動時・手動・設定の変更）
    case all
    /// 全ソースが対象だが、前回の収集から変わっていないと確かめられたソースは収集しない（5 分ごと。Issue #78）
    case periodic
    /// 確定履歴だけ（確定のたび。DSN-002 §3）
    case history

    /// 全ソースを対象にするか（フッターの構築中の表示と、周期の数え直しに使う）
    var coversAllSources: Bool {
        self != .history
    }

    /// 後続の再構築へまとめるときの対象。全件 > 周期 > 履歴だけ の順に広い方にする
    func merged(with other: Self) -> Self {
        if self == .all || other == .all {
            return .all
        }
        return self == .periodic || other == .periodic ? .periodic : .history
    }
}

/// 再構築 1 回分の結果。
struct CandidateRebuildOutcome: Sendable {
    /// 収集したソースと、その収集で出た警告。収集した候補が前回と同じで差し替えを省いたソースも含む
    var replaced: [CandidateSourceKind: [CandidateSourceWarning]] = [:]
    /// 収集したソースのうち、変更の検知の記録を作ったものと、その記録（ChangeTrackingCandidateSource の ChangeMarker）
    var markers: [CandidateSourceKind: any Sendable] = [:]
    /// 収集した候補が前回と同じだったため、差し替えを省いたソース
    var identical: Set<CandidateSourceKind> = []
    /// 前回の収集から変わっていないと確かめられたため、収集しなかったソース（周期の再構築のみ）
    var unchanged: Set<CandidateSourceKind> = []
    /// キャンセルされたため差し替えなかったソース
    var cancelled: Set<CandidateSourceKind> = []
    /// キャンセル以外のエラー（CandidateSource の契約外）で差し替えなかったソースと、エラーの型名
    var failed: [CandidateSourceKind: String] = [:]
    /// 設定から外れたため候補を取り除いたソース
    var removed: Set<CandidateSourceKind> = []
    var elapsed: Duration = .zero
}

/// 候補ソースを走査して CandidateIndex に反映する、再構築 1 回分の処理。呼び出し元のアクターに依らず動く。
enum CandidateRebuildCycle {
    private enum SourceResult: Sendable {
        case replaced(CandidateSourceKind, [CandidateSourceWarning], marker: (any Sendable)?, didReplace: Bool)
        case unchanged(CandidateSourceKind)
        case cancelled(CandidateSourceKind)
        case failed(CandidateSourceKind, errorType: String)
    }

    /// 設定から外れたソースの候補を取り除き、`refreshes` のソースを並行して走査する。
    ///
    /// - ソースごとに、走査を終えた時点でそのソースの候補だけを差し替える。遅いルートの走査を待たずに
    ///   履歴などの速いソースを反映するため（UX-001 §5「履歴分は即時表示」）。
    /// - 前回の収集の記録を渡されたソースは、先に変更の有無を確かめ、変わっていなければ走査も差し替えもしない（Issue #78）。
    /// - キャンセルされたソースは差し替えない。途中までの結果で既存の候補を減らさないため。
    ///   取り除く処理（空での差し替え）はキャンセルされても行う。消えたルートの候補を残さないため。
    /// - 同じ kind を含む `refreshes` を渡さないこと（同じソースの差し替えが並行すると後勝ちになる）。
    static func run(
        refreshes: [CandidateSourceRefresh],
        removing staleKinds: Set<CandidateSourceKind>,
        in index: CandidateIndex
    ) async -> CandidateRebuildOutcome {
        let startedAt = ContinuousClock.now
        var outcome = CandidateRebuildOutcome(removed: staleKinds)
        for kind in staleKinds {
            await index.replace(source: kind, with: [])
        }
        let results = await withTaskGroup(of: SourceResult.self) { group in
            for refresh in refreshes {
                group.addTask {
                    await self.refresh(refresh, in: index)
                }
            }
            var results: [SourceResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        for result in results {
            switch result {
            case .replaced(let kind, let warnings, let marker, let didReplace):
                outcome.replaced[kind] = warnings
                outcome.markers[kind] = marker
                if !didReplace {
                    outcome.identical.insert(kind)
                }
            case .unchanged(let kind):
                outcome.unchanged.insert(kind)
            case .cancelled(let kind):
                outcome.cancelled.insert(kind)
            case .failed(let kind, let errorType):
                outcome.failed[kind] = errorType
            }
        }
        outcome.elapsed = startedAt.duration(to: .now)
        return outcome
    }

    private static func refresh(_ refresh: CandidateSourceRefresh, in index: CandidateIndex) async -> SourceResult {
        let source = refresh.source
        let tracking = source as? any ChangeTrackingCandidateSource
        if let marker = refresh.marker, let tracking, await !tracking.hasChanged(sinceAnyMarker: marker) {
            return .unchanged(source.kind)
        }
        let snapshot: CandidateSourceSnapshot
        let marker: (any Sendable)?
        do {
            if let tracking {
                (snapshot, marker) = try await tracking.trackedSnapshotWithAnyMarker()
            } else {
                (snapshot, marker) = (try await source.snapshot(), nil)
            }
            // キャンセルを見ずに返したソースの結果でも、キャンセル後は差し替えない
            try Task.checkCancellation()
        } catch {
            // キャンセル後に別のエラーで終わった場合も、失敗ではなく取り消しとして扱う
            guard !(error is CancellationError), !Task.isCancelled else {
                return .cancelled(source.kind)
            }
            return .failed(source.kind, errorType: String(describing: type(of: error)))
        }
        let didReplace = await index.replace(source: source.kind, with: snapshot.items)
        return .replaced(source.kind, snapshot.warnings, marker: marker, didReplace: didReplace)
    }
}
