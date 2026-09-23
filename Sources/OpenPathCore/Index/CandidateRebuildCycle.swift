/// 再構築 1 回分の対象。
enum CandidateRebuildScope: Sendable, Equatable {
    /// 全ソース（起動時・周期・手動・設定の変更）
    case all
    /// 確定履歴だけ（確定のたび。DSN-002 §3）
    case history

    /// 後続の再構築へまとめるときの対象。どちらかが全ソースなら全ソース
    func merged(with other: Self) -> Self {
        self == .all || other == .all ? .all : .history
    }
}

/// 再構築 1 回分の結果。
struct CandidateRebuildOutcome: Sendable {
    /// 走査を終えて候補を差し替えたソースと、その収集で出た警告
    var replaced: [CandidateSourceKind: [CandidateSourceWarning]] = [:]
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
        case replaced(CandidateSourceKind, [CandidateSourceWarning])
        case cancelled(CandidateSourceKind)
        case failed(CandidateSourceKind, errorType: String)
    }

    /// 設定から外れたソースの候補を取り除き、`sources` を並行して走査する。
    ///
    /// - ソースごとに、走査を終えた時点でそのソースの候補だけを差し替える。遅いルートの走査を待たずに
    ///   履歴などの速いソースを反映するため（UX-001 §5「履歴分は即時表示」）。
    /// - キャンセルされたソースは差し替えない。途中までの結果で既存の候補を減らさないため。
    ///   取り除く処理（空での差し替え）はキャンセルされても行う。消えたルートの候補を残さないため。
    /// - 同じ kind を含む `sources` を渡さないこと（同じソースの差し替えが並行すると後勝ちになる）。
    static func run(
        sources: [any CandidateSource],
        removing staleKinds: Set<CandidateSourceKind>,
        in index: CandidateIndex
    ) async -> CandidateRebuildOutcome {
        let startedAt = ContinuousClock.now
        var outcome = CandidateRebuildOutcome(removed: staleKinds)
        for kind in staleKinds {
            await index.replace(source: kind, with: [])
        }
        let results = await withTaskGroup(of: SourceResult.self) { group in
            for source in sources {
                group.addTask {
                    await refresh(source, in: index)
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
            case .replaced(let kind, let warnings):
                outcome.replaced[kind] = warnings
            case .cancelled(let kind):
                outcome.cancelled.insert(kind)
            case .failed(let kind, let errorType):
                outcome.failed[kind] = errorType
            }
        }
        outcome.elapsed = startedAt.duration(to: .now)
        return outcome
    }

    private static func refresh(_ source: any CandidateSource, in index: CandidateIndex) async -> SourceResult {
        let snapshot: CandidateSourceSnapshot
        do {
            snapshot = try await source.snapshot()
            // キャンセルを見ずに返したソースの結果でも、キャンセル後は差し替えない
            try Task.checkCancellation()
        } catch {
            // キャンセル後に別のエラーで終わった場合も、失敗ではなく取り消しとして扱う
            guard !(error is CancellationError), !Task.isCancelled else {
                return .cancelled(source.kind)
            }
            return .failed(source.kind, errorType: String(describing: type(of: error)))
        }
        await index.replace(source: source.kind, with: snapshot.items)
        return .replaced(source.kind, snapshot.warnings)
    }
}
