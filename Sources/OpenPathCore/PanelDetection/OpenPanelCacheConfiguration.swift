/// `OpenPanelLocator` のキャッシュの設定。
public struct OpenPanelCacheConfiguration: Equatable, Sendable {
    /// 覚えておく要素の数の既定値。破棄の通知を取りこぼしても（観測を外したアプリの要素など）際限なく増えないようにする。
    public static let defaultCapacity = 256
    /// 確定ボタンかファイル一覧が見つからなかった候補を、最初に判定し直すまでの待ち時間の既定値。
    public static let defaultInitialRecheckDelay: Duration = .milliseconds(250)
    /// 判定し直す回数の既定値。待ち時間は 1 回ごとに倍にする（250ms → 500ms → 1s → 2s）。
    public static let defaultMaxRechecks = 4

    /// 覚えておく要素の数。超えたら最後に使ってから長いものから忘れる。
    public let capacity: Int
    public let initialRecheckDelay: Duration
    /// この回数だけ判定し直しても見つからなければ、パネルではないと確定する。
    public let maxRechecks: Int

    /// - Parameters:
    ///   - capacity: 覚えておく要素の数。負の値は 0 として扱う。
    ///   - initialRecheckDelay: 最初に判定し直すまでの待ち時間。
    ///   - maxRechecks: 判定し直す回数。負の値は 0 として扱う。
    public init(
        capacity: Int = defaultCapacity,
        initialRecheckDelay: Duration = defaultInitialRecheckDelay,
        maxRechecks: Int = defaultMaxRechecks
    ) {
        self.capacity = max(0, capacity)
        self.initialRecheckDelay = initialRecheckDelay
        self.maxRechecks = max(0, maxRechecks)
    }

    /// 判定し直した回数が completedRechecks のとき、次に判定し直すまでの待ち時間。
    func recheckDelay(afterRechecks completedRechecks: Int) -> Duration {
        initialRecheckDelay * (1 << completedRechecks)
    }
}
