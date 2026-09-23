/// 候補ソースの全件の再構築（`CandidateIndexRebuilder.isRebuilding`）の変化から、
/// パレットのフッターに「候補を構築中…」を出すかと、表示中の候補を引き直すかを決める（UX-001 §5）。
///
/// 構築中の表示は起動後の最初の構築の間だけにする。候補が揃う前の空振りを説明するための表示で、
/// 5 分ごとの再構築のたびに出すと、候補が揃っているのにフッターが切り替わってちらつくため。
public struct CandidateBuildProgress: Equatable, Sendable {
    /// フッターに構築中を表示するか
    public private(set) var showsBuildingStatus = false
    private var isRebuilding = false
    private var hasFinishedFirstBuild = false

    public init() {}

    /// 再構築中かの変化を反映する。
    /// - Returns: 全件の再構築を終えたとき true。候補が差し替わったので、表示中のパレットの候補を引き直す契機にする。
    public mutating func update(isRebuilding newValue: Bool) -> Bool {
        defer { showsBuildingStatus = isRebuilding && !hasFinishedFirstBuild }
        guard newValue != isRebuilding else { return false }
        isRebuilding = newValue
        guard !newValue else { return false }
        hasFinishedFirstBuild = true
        return true
    }
}
