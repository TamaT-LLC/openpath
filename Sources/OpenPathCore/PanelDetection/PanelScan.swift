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
    /// ウィンドウを列挙できなかった（アプリが応答しない等）。パネルの有無が分からないため、追跡中のパネルは消えたとみなさない。
    case unavailable
}

/// 観測中のアプリのウィンドウ一覧（`kAXWindowsAttribute`）を取得できなかった理由。
/// Core に AX の型を持ち込まないため、`AXError` のうち扱いを分けるものだけを写す。
public enum WindowListError: Equatable, Sendable {
    /// 属性に値がない（`kAXErrorNoValue`）。ウィンドウがない
    case noValue
    /// アプリの要素が無効（`kAXErrorInvalidUIElement`）。アプリが終了した
    case invalidElement
    /// 属性に対応していない（`kAXErrorAttributeUnsupported`）
    case attributeUnsupported
    /// 応答がない等で完了できなかった（`kAXErrorCannotComplete`）
    case cannotComplete
    /// 上記以外
    case other
}

extension PanelScanOutcome {
    /// ウィンドウ一覧を取得できなかったときの走査結果。
    /// パネルがないと言い切れるのは、ウィンドウがない場合とアプリが終了した場合だけ。
    /// それ以外（属性に対応していない、応答がない等）は取得できなかっただけなので `unavailable` とし、
    /// 追跡中のパネルを誤って消えたとみなさないようにする。
    public init(windowListError: WindowListError) {
        switch windowListError {
        case .noValue, .invalidElement:
            self = .found([])
        case .attributeUnsupported, .cannotComplete, .other:
            self = .unavailable
        }
    }
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
