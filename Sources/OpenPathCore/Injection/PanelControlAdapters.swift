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
    /// kAXValue の文字列（入力欄に入っている値）。値が無い・文字列でなければ nil。
    func value() async throws -> String?
    /// kAXFocused（要素がキー入力の受け先か）。値が無ければ false。
    /// - Throws: 要素が消えていれば `.panelGone`、読めなければ（属性が無い等）`.axError`。
    func isFocused() async throws -> Bool
    /// kAXFocused に true をセットし、要素をキー入力の受け先にする。
    func focus() async throws
}

/// 移動先シートの候補リスト（macOS 13 以降の移動先シートが入力欄の下に出す、移動先の候補）。
@MainActor
public protocol GoToSuggestionListReading {
    /// 選ばれている候補が指すパス。選択が無い・パスを読めない行（見出し等）なら nil。
    /// - Throws: 読めなければ投げる（リストが消えていれば `InjectionError.panelGone`、AX の失敗は `.axError`、
    ///   読み取りの期限を超えたら `ScanCutoff.Reached`）。呼び出し側は選択を読めなかったものとして扱う。
    func selectedPath() async throws -> String?
}

/// 移動先シートの入力欄と、確定に押すボタン・候補リスト。
public struct GoToFieldControls {
    public let field: any PanelElementOperating
    /// 「移動」/「Go」ボタン。無ければ Return で確定する（macOS 13 以降の移動先シートにはボタンが無い）。
    public let goButton: (any PanelElementOperating)?
    /// 入力欄と同じシートの候補リスト。無ければ nil。
    public let suggestionList: (any GoToSuggestionListReading)?

    public init(
        field: any PanelElementOperating,
        goButton: (any PanelElementOperating)?,
        suggestionList: (any GoToSuggestionListReading)? = nil
    ) {
        self.field = field
        self.goButton = goButton
        self.suggestionList = suggestionList
    }
}

/// 移動先シートの入力欄を探す（副方式の DSN-001 §3.2 ステップ 1 と、主方式の確定前の確認）。
@MainActor
public protocol GoToFieldLocating {
    /// 注入の最初に記録したウィンドウ（とそのシート）から、移動先シートの入力欄を探す（どの要素を選ぶかは `GoToFieldSearch`）。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Returns: 見つからなければ nil。
    /// - Throws: 注入先を特定できなければ `InjectionError`、打ち切ったら `ScanCutoff.Reached`。
    func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls?
}

/// auto_confirm: パネルの確定ボタン（「開く」等）を探す（DSN-001 §3.1 ステップ 8）。
@MainActor
public protocol OpenButtonLocating {
    /// 注入の最初に記録したウィンドウ（とそのシート）から、確定ボタンを探す（どの要素を選ぶかは `OpenButtonSearch`）。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Returns: 見つからなければ nil。
    /// - Throws: 注入先を特定できなければ `InjectionError`、打ち切ったら `ScanCutoff.Reached`。
    func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)?
}

/// 注入先の状態。
public enum InjectionTargetStatus: Equatable, Sendable {
    /// 注入先のアプリが最前面で、注入先のウィンドウ（またはそのシート）にフォーカスがある。
    case available
    /// 注入先のウィンドウが最前面でない（別のアプリ、または同じアプリの別のウィンドウに切り替わった）。
    case notFrontmost
    /// 注入先のウィンドウが消えた。
    case gone
}

/// 注入先（注入を始めた時点の最前面アプリと、そのフォーカス中のウィンドウ）の記録と確認。
///
/// キー入力はその時点のキーウィンドウに届くため、注入中に別のアプリ・ウィンドウへ切り替わると ⌘A / ⌘V / Return がそこに届く
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
