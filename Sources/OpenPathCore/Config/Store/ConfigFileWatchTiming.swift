/// 設定ファイルの監視のタイミング。テストでは短くして、実時間の待ちを減らす。
public struct ConfigFileWatchTiming: Sendable, Equatable {
    /// rename / delete の後、エディタが新しいファイルを書き終えるのを待ってから開き直す（DSN-002 §6）
    public static let defaultReopenDelay: Duration = .milliseconds(200)
    /// 開き直しを試す回数。既定では約 2 秒待ってもファイルが現れなければ諦め、再作成はディレクトリの監視で拾う
    public static let defaultMaxReopenAttempts = 10
    /// 1 回の保存で続けて届くイベント（切り詰め → 書き込み、rename → 再オープン等）を 1 回の読み込みにまとめる
    public static let defaultDebounceInterval: Duration = .milliseconds(100)

    public static let `default` = ConfigFileWatchTiming()

    /// rename / delete を検知してからファイルを開き直すまでの待ち時間。開けなかったときの再試行の間隔も兼ねる
    public let reopenDelay: Duration
    /// 開き直しを試す最大回数（1 以上）
    public let maxReopenAttempts: Int
    /// 最後のイベントからこの時間だけ次のイベントが無ければ読み込み直す
    public let debounceInterval: Duration

    public init(
        reopenDelay: Duration = defaultReopenDelay,
        maxReopenAttempts: Int = defaultMaxReopenAttempts,
        debounceInterval: Duration = defaultDebounceInterval
    ) {
        self.reopenDelay = reopenDelay
        self.maxReopenAttempts = maxReopenAttempts
        self.debounceInterval = debounceInterval
    }
}
