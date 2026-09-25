/// パネルの候補にした理由（DSN-001 §2.2 の条件 1）。
public enum PanelCandidateReason: String, Equatable, Sendable {
    /// ロールかサブロールが AXSheet（`beginSheetModal` のパネル、サンドボックスアプリのパネル）。
    case sheet
    /// サブロールが AXDialog（`runModal` のパネル）。
    case dialog
    /// AXIdentifier が `open-panel`（非モーダルのパネル。サブロールは AXStandardWindow になる、Issue #83）。
    case openPanelIdentifier
}

/// パネル判定の診断 1 件（debug ログ用、Issue #83）。
///
/// `OpenPanelLocator.locate(in:reader:now:diagnostics:)` が、新しく分かったことがあったときだけ作る。
/// - トップレベルのウィンドウを初めて見て、候補でないと分かったとき（`result` が `.notCandidate`）
/// - 候補（ダイアログ・シート・open-panel のウィンドウ）を判定したとき（判定し直しを含む）
///
/// キャッシュが効いている間は作らないため、200ms ごとのポーリングでもログは増え続けない。
public struct OpenPanelDiagnostic: Equatable, Sendable {
    /// 調べた要素。
    public enum Target: Equatable, Sendable {
        /// トップレベルのウィンドウ（`kAXWindowsAttribute` の 1 つ）。
        case window
        /// ウィンドウの子のシート。nesting はウィンドウの子を 1 と数える。
        case sheet(nesting: Int)
    }

    /// 判定の結果。
    public enum Result: Equatable, Sendable {
        /// 候補（条件 1）でないため判定しなかった。
        case notCandidate
        /// NSOpenPanel と判定した。
        case openPanel
        /// 保存パネルと判定した（条件 4）。
        case savePanel
        /// 確定ボタンかファイル一覧が見つからなかった（条件 2・3）。willRecheck なら、描画途中の可能性があるため後で判定し直す。
        case missingElements(hasConfirmButton: Bool, hasFileList: Bool, willRecheck: Bool)
        /// 候補の中身を読めなかった（応答のタイムアウトなど）。判定できないため、次の走査で判定し直す。
        /// 走査のたびに失敗しても、候補ごとに 1 回だけ記録する。
        case unreadable
    }

    public let target: Target
    public let role: String?
    public let subrole: String?
    /// `AXIdentifier`（開発者が付ける識別子。NSOpenPanel のウィンドウは `open-panel`）。
    public let identifier: String?
    /// 候補にした理由。候補でなければ nil。
    public let candidateReason: PanelCandidateReason?
    public let result: Result
    /// 何回目の判定か（1 が最初、2 以降が判定し直し）。候補でなければ 0。
    public let attempt: Int
    /// 判定の回数の上限（最初の 1 回と、判定し直しの回数）。
    public let maxAttempts: Int
    /// 子孫の要約。候補でなければ nil。
    public let details: OpenPanelClassificationDetails?

    public init(
        target: Target,
        role: String?,
        subrole: String?,
        identifier: String?,
        candidateReason: PanelCandidateReason?,
        result: Result,
        attempt: Int,
        maxAttempts: Int,
        details: OpenPanelClassificationDetails?
    ) {
        self.target = target
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.candidateReason = candidateReason
        self.result = result
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.details = details
    }
}

/// `OpenPanelLocator.locate(in:reader:now:diagnostics:)` で集めた診断。
public struct OpenPanelDiagnosticReport: Equatable, Sendable {
    /// 新しく分かったこと（ウィンドウ・候補ごと）。
    public var entries: [OpenPanelDiagnostic] = []
    /// 診断のためだけに行った AX の読み取りの回数。判定のコストのログ（`axCalls`）から除くために数える。
    public var diagnosticReadCount = 0

    public init() {}
}
