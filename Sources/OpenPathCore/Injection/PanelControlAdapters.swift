// 副方式（DSN-001 §3.2）・auto_confirm（§3.1 ステップ 8）・注入先の確認が使う、OS 側の操作（AX / NSWorkspace）の抽象。
// 実体は OpenPathMac の薄いアダプタで実装し、Core からはこのプロトコル越しにのみ扱う。

/// AX で操作するパネル内の要素（入力欄・ボタン）。
/// 各操作は失敗を `InjectionError` で投げる（要素が消えていれば `.panelGone`、それ以外の AX の失敗は `.axError`）。
@MainActor
public protocol PanelElementOperating {
    /// kAXValue に value を直接書き込む（DSN-001 §3.2 ステップ 2）。
    /// 書き込めない場合（kAXErrorAttributeUnsupported を含む）は失敗として投げる。
    func setValue(_ value: String) async throws
    /// AXPress（ボタンの押下）。
    func press() async throws
    /// kAXConfirmAction（入力欄の確定）。
    func confirm() async throws
    /// 要素が消えたか。押下で閉じたシートやパネルの要素は消える。
    func hasDisappeared() async -> Bool
}

/// 副方式で値をセットする入力欄と、確定に押すボタン。
public struct GoToFieldControls {
    public let field: any PanelElementOperating
    /// 「移動」/「Go」ボタン。無ければ入力欄を確定する（kAXConfirmAction）。
    public let goButton: (any PanelElementOperating)?

    public init(field: any PanelElementOperating, goButton: (any PanelElementOperating)?) {
        self.field = field
        self.goButton = goButton
    }
}

/// 副方式: 移動先シートの入力欄を探す（DSN-001 §3.2 ステップ 1）。
@MainActor
public protocol GoToFieldLocating {
    /// 注入先のフォーカス中のウィンドウから、移動先シートの入力欄を探す（どの要素を選ぶかは `GoToFieldSearch`）。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Returns: 見つからなければ nil。
    /// - Throws: 注入先を特定できなければ `InjectionError`、打ち切ったら `ScanCutoff.Reached`。
    func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls?
}

/// auto_confirm: パネルの確定ボタン（「開く」等）を探す（DSN-001 §3.1 ステップ 8）。
@MainActor
public protocol OpenButtonLocating {
    /// 注入先のフォーカス中のウィンドウから、確定ボタンを探す（どの要素を選ぶかは `OpenButtonSearch`）。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Returns: 見つからなければ nil。
    /// - Throws: 注入先を特定できなければ `InjectionError`、打ち切ったら `ScanCutoff.Reached`。
    func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)?
}

/// 注入先の状態。
public enum InjectionTargetStatus: Equatable, Sendable {
    /// 注入先のアプリが最前面で、注入先のウィンドウが残っている。
    case available
    /// 注入先のアプリが最前面でない（別のアプリに切り替わった）。
    case notFrontmost
    /// 注入先のウィンドウが消えた。
    case gone
}

/// 注入先（注入を始めた時点の最前面アプリと、そのフォーカス中のウィンドウ）の記録と確認。
///
/// キー入力はその時点のキーウィンドウに届くため、注入中に別のアプリへ切り替わると ⌘A / ⌘V / Return がそのアプリに届く
/// （チャットアプリでの送信など）。これを防ぐため、キー操作とパネルへの AX 操作の直前ごとに確かめる。
@MainActor
public protocol InjectionTargetGuarding {
    /// 最前面アプリとそのフォーカス中のウィンドウを注入先として記録する。以降の確認と要素探しはこの注入先に対して行う。
    /// - Throws: 注入先が無ければ `InjectionError.panelGone`、AX の失敗は `.axError`、打ち切ったら `ScanCutoff.Reached`。
    func captureTarget(cutoff: ScanCutoff) async throws
    /// 記録した注入先の状態。記録していなければ `.gone`。
    /// - Throws: 状態を確かめられなければ `InjectionError.axError`、打ち切ったら `ScanCutoff.Reached`。
    func currentStatus(cutoff: ScanCutoff) async throws -> InjectionTargetStatus
}

/// 副方式と auto_confirm の待ち時間（DSN-001 §3.1 ステップ 8, §3.2）。
public struct PanelControlTiming: Equatable, Sendable {
    /// 移動先シートを確定してから「開く」を押すまでの待ち時間（ステップ 8）。パネルの移動が反映されるのを待つ。
    public let openButtonDelay: Duration
    /// 入力欄・ボタンを探す AX の走査の上限。
    public let controlLookupLimit: Duration

    public init(openButtonDelay: Duration, controlLookupLimit: Duration) {
        self.openButtonDelay = openButtonDelay
        self.controlLookupLimit = controlLookupLimit
    }

    /// 走査の上限は、主方式のシート待ち（600ms）と「開く」の待機（300ms）を足しても
    /// AppCoordinator の全体タイムアウト（1.5 秒）に収まりやすい長さにする。
    public static let standard = PanelControlTiming(
        openButtonDelay: .milliseconds(300),
        controlLookupLimit: .milliseconds(300)
    )
}

/// Core が決める AX のエラーコード。値は AXError の rawValue と同じ（Core に ApplicationServices を持ち込まないため数値で持つ）。
public enum InjectionAXErrorCode {
    /// kAXErrorFailure: 操作する要素が見つからない、アダプタが想定外の失敗をした。
    public static let failure: Int32 = -25_200
    /// kAXErrorCannotComplete: 要素探しや注入先の確認が期限内に終わらなかった。
    public static let cannotComplete: Int32 = -25_204
}
