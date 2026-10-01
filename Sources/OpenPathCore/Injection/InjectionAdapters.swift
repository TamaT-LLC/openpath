import Foundation

// 主方式の手順（GoToFolderPasteSequencer）が使う、OS 側の操作の抽象。
// 実体（NSPasteboard / CGEvent / AX）は OpenPathMac の薄いアダプタで実装し、Core からはこのプロトコル越しにのみ扱う。

/// ペーストボードのアイテム 1 件の読み取り（NSPasteboardItem の抽象）。
@MainActor
public protocol PasteboardItemReading {
    /// アイテムが持つ型。優先度の高い順。
    var types: [String] { get }
    /// 型のデータ。提供元が応答しない場合などは nil。
    func data(forType type: String) -> Data?
}

/// 注入に使うペーストボード（NSPasteboard.general の抽象）。
@MainActor
public protocol PasteboardAccessing: AnyObject {
    /// 内容の所有者が変わるたびに増える値（NSPasteboard.changeCount）。
    var changeCount: Int { get }
    var items: [any PasteboardItemReading] { get }
    /// 既存の内容を消し、snapshot の内容を書き込む。アイテムが無ければ消すだけ。
    /// - Returns: 書き込めたか。失敗しても既存の内容は消えている場合がある。
    func replaceContents(with snapshot: PasteboardSnapshot) -> Bool
}

/// 主方式で送るキー操作（DSN-001 §3.1）。どのキーで送るか（`spec`）は `InjectionKeyLayout.swift`、
/// 入力ソースのキー配列に合わせた仮想キーコードへの対応は `InjectionKeyCodeResolver` と OpenPathMac 側が持つ。
public enum InjectionKeyStroke: Equatable, Hashable, Sendable, CaseIterable {
    /// ⌘⇧G: 移動先シートを開く
    case goToFolder
    /// ⌘A: 入力欄の既存値を全選択する
    case selectAll
    /// ⌘V: パスを貼り付ける
    case paste
    /// Return: シートを確定してパネルを移動させる
    case returnKey
    /// /: ファイル一覧にフォーカスがあるときに移動先シートを開く（⌘⇧G でシートが出なかったときの代替）。
    /// 入力欄にフォーカスがあると文字として入ってしまうため、ファイル一覧にフォーカスがあるときだけ送る。
    case slash
}

/// キーイベントを送る経路。
public enum InjectionKeyRoute: String, Equatable, Sendable {
    /// 注入先のプロセスへ直接送る（`CGEvent.postToPid`）。他アプリのグローバルホットキー（Raycast の ⌘⇧G 等）や
    /// イベントタップを経由しないため、横取りされない。アプリが前面でなくても届くため、送る前の注入先の確認は欠かせない。
    case targetProcess
    /// 物理キーボードと同じ経路でシステムへ送る（`CGEvent.post(tap: .cghidEventTap)`）。
    /// 最前面アプリのキーウィンドウに届くが、他アプリのグローバルホットキーに先に評価され、横取りされることがある。
    case systemWide
}

/// 送る準備ができたキー操作（送り先とキーイベントが決まっている）。
/// 送る直前の注入先の確認と送出の間に待ちを挟まないよう、`post()` は同期的に送るだけにする。
@MainActor
public struct PreparedKeyStroke {
    private let send: @MainActor () -> Void

    public init(send: @escaping @MainActor () -> Void) {
        self.send = send
    }

    /// 送る。
    public func post() {
        send()
    }
}

/// キー操作の送出（CGEvent の抽象）。
///
/// 送り先を決める AX の読み取りなど待ちを伴う処理は `prepare` で済ませ、呼び出し側は注入先の確認の直後に `post()` で送る。
/// 送り先を決めている間にフォーカスが移ったりキャンセルされたりしても、送る前の確認で止められるようにするため。
@MainActor
public protocol KeyStrokePosting {
    /// - Parameter route: 送る経路。`.targetProcess` では、注入先のアプリ（パネルを別プロセスが描く場合はフォーカス中の要素のプロセス）へ送る。
    /// - Throws: キーイベントを作れない・送り先を決められない場合。
    func prepare(_ keyStroke: InjectionKeyStroke, via route: InjectionKeyRoute) async throws -> PreparedKeyStroke
}

/// ⌘⇧G で開く移動先シートの出現判定（AX の抽象）。
@MainActor
public protocol GoToSheetDetecting {
    /// ⌘⇧G を送る前の状態を基準として記録し、以降の判定に使うプローブを返す。
    /// 基準と比べるのは、パネル自体がシートとして表示されている場合などに、送出前からあるシートを出現と誤認しないため。
    /// - Parameter cutoff: 基準を記録する走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Throws: 注入先を特定できない場合は `InjectionError`（`.panelGone` / `.axError`）、打ち切った場合は `ScanCutoff.Reached`。
    func makeProbe(cutoff: ScanCutoff) async throws -> any GoToSheetProbe
}

/// 基準を記録済みの移動先シートの判定。
@MainActor
public protocol GoToSheetProbe {
    /// ⌘⇧G を送る前（基準の時点）から移動先シートが開いているか（基準の走査で移動先シートの入力欄を見つけたか。Issue #95）。
    /// 開いているシートに ⌘⇧G を送っても新しいシートは出ないため、呼び出し側は ⌘⇧G を送らずにそのシートを使う。
    var isSheetAlreadyShown: Bool { get }

    /// 基準の時点から移動先シートが現れたか。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Throws: 打ち切った場合は `ScanCutoff.Reached`。
    func isSheetShown(cutoff: ScanCutoff) async throws -> Bool
}
