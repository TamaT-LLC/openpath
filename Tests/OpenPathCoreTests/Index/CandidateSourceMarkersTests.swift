import Testing

@testable import OpenPathCore

/// 再構築 1 回でどのソースを収集し、どのソースは変更を確かめるだけにするか（Issue #78）。
/// CandidateIndexRebuilder から切り出した純粋なロジックで、ソースを呼ばずに判定だけを確かめる。
@Suite("CandidateSourceMarkers: 収集するソースの判定")
struct CandidateSourceMarkersTests {
    private typealias F = RebuilderFixtures

    private static let history = ScriptedCandidateSource(kind: .history)
    private static let first = ScriptedCandidateSource(kind: .root(F.firstRoot))
    private static let second = ScriptedCandidateSource(kind: .root(F.secondRoot))
    private static let ghq = ScriptedCandidateSource(kind: .ghq)
    private static let sources: [any CandidateSource] = [history, first, second, ghq]

    /// 変更を確かめられない（ChangeTrackingCandidateSource でない）ソース
    private struct PlainSource: CandidateSource {
        let kind: CandidateSourceKind

        func snapshot() async throws -> CandidateSourceSnapshot {
            CandidateSourceSnapshot(items: [])
        }
    }

    /// `kinds` を収集し、`markers` の記録を受け取った再構築の結果
    private static func collected(
        _ kinds: [CandidateSourceKind],
        markers: [CandidateSourceKind: Int] = [:]
    ) -> CandidateRebuildOutcome {
        var outcome = CandidateRebuildOutcome()
        for kind in kinds {
            outcome.replaced[kind] = []
        }
        outcome.markers = markers.mapValues { $0 as any Sendable }
        return outcome
    }

    /// 収集するソースの kind と、変更を確かめるために渡す記録（版）
    private static func summary(_ refreshes: [CandidateSourceRefresh]) -> [String] {
        refreshes.map { refresh in
            let marker = refresh.marker.map { "@\($0 as? Int ?? -1)" } ?? ""
            return "\(refresh.source.kind)\(marker)"
        }
    }

    private static func label(_ kind: CandidateSourceKind, marker: Int? = nil) -> String {
        "\(kind)" + (marker.map { "@\($0)" } ?? "")
    }

    // MARK: - 収集するソース

    @Test("記録が無ければ、周期の再構築でも全ソースを収集する")
    func collectsAllWithoutMarkers() {
        let markers = CandidateSourceMarkers()

        let refreshes = markers.refreshes(for: .periodic, sources: Self.sources)

        #expect(Self.summary(refreshes) == Self.sources.map { Self.label($0.kind) })
    }

    @Test("周期の再構築では、記録のあるソースに記録を渡して変更を確かめさせる")
    func periodicPassesMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.history, .root(F.firstRoot), .ghq], markers: [.root(F.firstRoot): 1]))

        let refreshes = markers.refreshes(for: .periodic, sources: Self.sources)

        #expect(Self.summary(refreshes) == [
            Self.label(.history), Self.label(.root(F.firstRoot), marker: 1), Self.label(.root(F.secondRoot)), Self.label(.ghq),
        ])
    }

    @Test("全件の再構築（起動時・手動・設定の変更）では、記録があっても確かめずに全ソースを収集する")
    func fullRebuildIgnoresMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot), .root(F.secondRoot)], markers: [.root(F.firstRoot): 1, .root(F.secondRoot): 2]))

        let refreshes = markers.refreshes(for: .all, sources: Self.sources)

        #expect(Self.summary(refreshes) == Self.sources.map { Self.label($0.kind) })
    }

    @Test("履歴だけの取り直しでは、履歴だけを収集する")
    func historyScopeCollectsHistoryOnly() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot)], markers: [.root(F.firstRoot): 1]))

        let refreshes = markers.refreshes(for: .history, sources: Self.sources)

        #expect(Self.summary(refreshes) == [Self.label(.history)])
    }

    @Test("変更を確かめられないソースには、同じ kind の記録があっても渡さない")
    func plainSourceIsAlwaysCollected() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot)], markers: [.root(F.firstRoot): 1]))

        let refreshes = markers.refreshes(for: .periodic, sources: [PlainSource(kind: .root(F.firstRoot))])

        #expect(Self.summary(refreshes) == [Self.label(.root(F.firstRoot))])
    }

    // MARK: - 記録の更新

    @Test("収集したソースの記録は新しい記録に置き換え、記録を返さなかったソースの記録は消す")
    func collectedSourcesReplaceMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot), .root(F.secondRoot)], markers: [.root(F.firstRoot): 1, .root(F.secondRoot): 1]))

        markers.update(with: Self.collected([.root(F.firstRoot), .root(F.secondRoot)], markers: [.root(F.firstRoot): 2]))

        #expect(Self.summary(markers.refreshes(for: .periodic, sources: [Self.first, Self.second])) == [
            Self.label(.root(F.firstRoot), marker: 2), Self.label(.root(F.secondRoot)),
        ])
    }

    @Test("変更が無かったソースの記録は残す")
    func unchangedSourcesKeepMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot)], markers: [.root(F.firstRoot): 1]))
        var outcome = CandidateRebuildOutcome()
        outcome.unchanged = [.root(F.firstRoot)]

        markers.update(with: outcome)

        #expect(Self.summary(markers.refreshes(for: .periodic, sources: [Self.first])) == [Self.label(.root(F.firstRoot), marker: 1)])
    }

    @Test("取り消し・失敗・除去したソースの記録は消す（次は変更を確かめずに収集する）")
    func cancelledFailedAndRemovedSourcesDropMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected(
            [.root(F.firstRoot), .root(F.secondRoot), .ghq],
            markers: [.root(F.firstRoot): 1, .root(F.secondRoot): 1, .ghq: 1]
        ))
        var outcome = CandidateRebuildOutcome()
        outcome.cancelled = [.root(F.firstRoot)]
        outcome.failed = [.root(F.secondRoot): "SomeError"]
        outcome.removed = [.ghq]

        markers.update(with: outcome)

        #expect(Self.summary(markers.refreshes(for: .periodic, sources: [Self.first, Self.second, Self.ghq])) == [
            Self.label(.root(F.firstRoot)), Self.label(.root(F.secondRoot)), Self.label(.ghq),
        ])
    }

    @Test("removeAll で記録をすべて消す（設定の変更で走査の条件が変わったとき）")
    func removeAllDropsMarkers() {
        var markers = CandidateSourceMarkers()
        markers.update(with: Self.collected([.root(F.firstRoot)], markers: [.root(F.firstRoot): 1]))

        markers.removeAll()

        #expect(Self.summary(markers.refreshes(for: .periodic, sources: [Self.first])) == [Self.label(.root(F.firstRoot))])
    }

    // MARK: - 契機の合流

    @Test(
        "後続の再構築へまとめるときは、全件 > 周期 > 履歴だけ の順に広い方にする",
        arguments: [
            (CandidateRebuildScope.all, CandidateRebuildScope.periodic, CandidateRebuildScope.all),
            (.periodic, .all, .all),
            (.all, .history, .all),
            (.periodic, .history, .periodic),
            (.history, .periodic, .periodic),
            (.periodic, .periodic, .periodic),
            (.history, .history, .history),
        ]
    )
    func scopesMerge(lhs: CandidateRebuildScope, rhs: CandidateRebuildScope, expected: CandidateRebuildScope) {
        #expect(lhs.merged(with: rhs) == expected)
    }

    @Test("全件と周期の再構築は全ソースの再構築として扱い、履歴だけの取り直しは扱わない")
    func fullScopes() {
        #expect(CandidateRebuildScope.all.coversAllSources)
        #expect(CandidateRebuildScope.periodic.coversAllSources)
        #expect(!CandidateRebuildScope.history.coversAllSources)
    }
}
