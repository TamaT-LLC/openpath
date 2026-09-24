/// 前回の収集から候補が変わったかを、収集し直すより安価に確かめられる候補ソース（Issue #78）。
///
/// 周期の再構築（CandidateIndexRebuilder）は、前回の収集で受け取った記録で変更の有無を確かめ、
/// 変わっていなければ収集も差し替えもしない。起動時・手動・設定の変更では、記録にかかわらず収集し直す。
public protocol ChangeTrackingCandidateSource: CandidateSource {
    /// 収集した時点の状態の記録
    associatedtype ChangeMarker: Sendable

    /// 候補を集め、後で変更の有無を確かめるための記録を添えて返す。
    ///
    /// 記録は集める前の状態で作ること（集めている間の変化を、次の確認で取りこぼさないため）。
    /// 記録を作れない（ルートを走査できない等）ときは nil を返す。次の周期も収集し直す。
    /// - Throws: キャンセルされた場合だけ `CancellationError`（`snapshot()` と同じ）。
    func trackedSnapshot() async throws -> (snapshot: CandidateSourceSnapshot, marker: ChangeMarker?)

    /// `marker` を記録した収集の後に、候補が変わった可能性があるか。確かめられないときも true を返す。
    func hasChanged(since marker: ChangeMarker) async -> Bool
}

extension ChangeTrackingCandidateSource {
    /// 記録の型を消して収集する。CandidateIndexRebuilder がソースの種類を問わず記録を持つため
    func trackedSnapshotWithAnyMarker() async throws -> (snapshot: CandidateSourceSnapshot, marker: (any Sendable)?) {
        let (snapshot, marker) = try await trackedSnapshot()
        return (snapshot, marker.map { $0 as any Sendable })
    }

    /// 型の合わない記録（別の種類のソースのもの）は確かめられないため、変わったものとして扱う
    func hasChanged(sinceAnyMarker marker: any Sendable) async -> Bool {
        guard let marker = marker as? ChangeMarker else {
            return true
        }
        return await hasChanged(since: marker)
    }
}
