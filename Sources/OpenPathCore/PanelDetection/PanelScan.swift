/// パネルの走査（観測中のアプリのウィンドウを列挙し、NSOpenPanel かどうかを判定する）の依頼。
/// 走査は AX のプロセス間呼び出しを伴い非同期に完了するため、結果を依頼と突き合わせて古い結果を捨てられるよう id を振る。
public struct PanelScanRequest: Equatable, Sendable {
    public let id: Int
    /// 走査するアプリのプロセス ID。
    public let processID: Int32

    public init(id: Int, processID: Int32) {
        self.id = id
        self.processID = processID
    }
}

/// 走査の結果。
public enum PanelScanOutcome: Equatable, Sendable {
    /// ウィンドウを列挙できた。NSOpenPanel と判定したものを並び順どおりに持つ（なければ空）。
    case found([PanelContext])
    /// ウィンドウを列挙できなかった（AX のエラー）。パネルの有無が分からないため、追跡中のパネルは消えたとみなさない。
    /// アプリの終了は NSWorkspace の終了通知（`PanelWatchInput.applicationTerminated`）で扱う。
    case unavailable
}

/// `PanelScanRequest` に対する結果。
public struct PanelScanResult: Equatable, Sendable {
    /// 対応する `PanelScanRequest.id`。
    public let requestID: Int
    public let outcome: PanelScanOutcome

    public init(requestID: Int, outcome: PanelScanOutcome) {
        self.requestID = requestID
        self.outcome = outcome
    }
}
