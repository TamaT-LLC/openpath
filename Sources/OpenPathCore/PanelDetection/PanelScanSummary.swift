/// 走査 1 回の要約（debug ログ用、Issue #83）。どのアプリのウィンドウを何枚見たのかを残す。
///
/// パネルがホストのウィンドウ一覧に現れているか（ダイアログを開いてもウィンドウの数が増えないなら、一覧の外にある）を、
/// QA のログから見分けるために使う。
public struct PanelScanSummary: Equatable, Sendable {
    /// 観測中のアプリのプロセス ID。
    public let processID: Int32
    /// 観測中のアプリの bundle id。分からなければ nil。
    public let bundleIdentifier: String?
    /// `kAXWindowsAttribute` のウィンドウの数。一覧を読めなかったら nil。
    public let windowCount: Int?
    /// 一覧を読めなかったときの AX のエラーコード（`AXError` の値）。
    public let axErrorCode: Int32?

    public init(processID: Int32, bundleIdentifier: String?, windowCount: Int?, axErrorCode: Int32?) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.windowCount = windowCount
        self.axErrorCode = axErrorCode
    }
}

/// 走査の要約を、直前に出したものと変わったときだけ出す。200ms ごとのポーリングで同じ行が並ばないようにする。
public struct PanelScanSummaryLog: Sendable {
    private var lastLogged: PanelScanSummary?

    public init() {}

    /// summary が直前に出したものと違えば、ログの文言を返して記録する。同じなら nil。
    public mutating func messageIfChanged(_ summary: PanelScanSummary) -> String? {
        guard summary != lastLogged else { return nil }
        lastLogged = summary
        return PanelWatchLogMessage.scanSummary(summary)
    }
}
