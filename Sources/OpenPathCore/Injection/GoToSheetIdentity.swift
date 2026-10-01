/// フォーカス中のウィンドウが「フォルダへ移動」シート（移動先シート）そのものかの判定（Issue #95）。
///
/// 注入の前から移動先シートが開いていると、アプリのフォーカス中のウィンドウ（kAXFocusedWindow）は、パネルではなく
/// 移動先シートになる（ロール AXSheet・サブロール無し・AXIdentifier `GoToWindow`。macOS 27 の自プロセスのパネルで確認）。
/// これを注入先として記録すると、確定でシートが閉じた後に注入先が消えたとみなされ、auto_confirm の「開く」も探せない。
/// そのため注入先の記録（`InjectionTargetGuard`）は、移動先シートならそれが付いたパネル（AXParent）を記録する。
///
/// シートとして付いたパネル（ロール AXSheet）と取り違えないよう、次のどちらかに当たるシートだけを移動先シートとみなす。
/// - AXIdentifier が `GoToWindow`
/// - 直下の子に移動先シートの入力欄（AXIdentifier `PathTextField`）がある（AXIdentifier が違う OS に備える）
///
/// AX から切り離し、要素の型と属性の読み方を呼び出し側から受け取ることでユニットテスト可能にしている。
public enum GoToSheetIdentity {
    /// 移動先シートの AXIdentifier（macOS 27 の自プロセスのパネルで確認）。
    static let goToSheetIdentifier = "GoToWindow"

    /// - Parameters:
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - role: window と、その直下の子にだけ呼ぶ。
    ///   - identifier: シートの window と、その直下の入力欄にだけ呼ぶ。
    ///   - children: シートの window にだけ呼ぶ（AXIdentifier で分かれば呼ばない）。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func isGoToSheet<Node>(
        _ window: Node,
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> Bool {
        try cutoff.throwIfReached()
        guard role(window) == GoToSheetScan.sheetRole else { return false }
        try cutoff.throwIfReached()
        if identifier(window) == goToSheetIdentifier {
            return true
        }
        try cutoff.throwIfReached()
        for child in children(window) {
            try cutoff.throwIfReached()
            guard let childRole = role(child), GoToSheetScan.pathFieldRoles.contains(childRole) else { continue }
            try cutoff.throwIfReached()
            if identifier(child) == GoToFieldSearch.pathFieldIdentifier {
                return true
            }
        }
        return false
    }
}
