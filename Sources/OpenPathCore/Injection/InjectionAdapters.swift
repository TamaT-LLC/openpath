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

/// 主方式で送るキー操作（DSN-001 §3.1）。仮想キーコードへの対応は OpenPathMac 側が持つ。
public enum InjectionKeyStroke: Equatable, Hashable, Sendable, CaseIterable {
    /// ⌘⇧G: 移動先シートを開く
    case goToFolder
    /// ⌘A: 入力欄の既存値を全選択する
    case selectAll
    /// ⌘V: パスを貼り付ける
    case paste
    /// Return: シートを確定してパネルを移動させる
    case returnKey
}

/// キー操作の送出（CGEvent の抽象）。キー入力はその時点のキーウィンドウに届く。
@MainActor
public protocol KeyStrokePosting {
    /// - Throws: キーイベントを作れず送れなかった場合。
    func post(_ keyStroke: InjectionKeyStroke) throws
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
    /// 基準の時点から移動先シートが現れたか。
    /// - Parameter cutoff: 走査の打ち切り条件。AX 操作のたびに確かめること。
    /// - Throws: 打ち切った場合は `ScanCutoff.Reached`。
    func isSheetShown(cutoff: ScanCutoff) async throws -> Bool
}
