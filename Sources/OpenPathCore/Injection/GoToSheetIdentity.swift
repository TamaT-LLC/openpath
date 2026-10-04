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

    /// フォーカス中のウィンドウが、注入先として記録したウィンドウに付いた移動先シートか（Issue #95、PR #118 のレビュー）。
    /// Return を送る直前の最後の確認に使う。移動先シートであること（`isGoToSheet`）に加え、注入先のウィンドウとの対応を
    /// 注入先の確認（`InjectionTargetGuard.currentStatus`）と同じ `InjectionWindowRelation` で確かめ、同じアプリの別のパネルに
    /// 付いた移動先シートを除く。対応を読めなければ（AXParent が無い）false。
    /// - Parameters:
    ///   - isSameElement: 同じ要素か（AX の往復を伴わない比較）。
    ///   - parent: AXParent。focusedWindow が注入先のウィンドウそのものでないときだけ呼ぶ。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func isGoToSheet<Node>(
        _ focusedWindow: Node,
        attachedTo targetWindow: Node,
        cutoff: ScanCutoff = .never,
        isSameElement: (Node, Node) -> Bool,
        parent: (Node) -> Node?,
        role: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> Bool {
        let isAttached = try InjectionWindowRelation.isTargetOrAttached(
            focusedWindow, to: targetWindow, cutoff: cutoff, isSameElement: isSameElement, parent: parent
        )
        guard isAttached else { return false }
        return try isGoToSheet(focusedWindow, cutoff: cutoff, role: role, identifier: identifier, children: children)
    }
}

/// フォーカス中のウィンドウと、注入先として記録したウィンドウの対応（PR #54・#118）。
/// キー入力はフォーカス中のウィンドウに届くため、それが記録したウィンドウそのものか、そのウィンドウに付いたシート
/// （AXParent が記録したウィンドウ。移動先シート・シートとして付いたパネル等）のときだけ、注入先にキーが届くとみなす。
/// 注入先の確認（`PanelControlAX.hasFocus`）と、Return の直前の移動先シートの確認（`GoToSheetIdentity.isGoToSheet(_:attachedTo:)`）で
/// 同じ対応づけを使い、注入先の確認が通るのに移動先シートの確認だけが通らない環境を作らない。
public enum InjectionWindowRelation {
    /// - Parameters:
    ///   - isSameElement: 同じ要素か（AX の往復を伴わない比較）。
    ///   - parent: AXParent。window が記録したウィンドウそのものでないときだけ呼ぶ。読めなければ nil（対応しないものとする）。
    /// - Throws: 打ち切り条件に達したら、AXParent を読まずに `ScanCutoff.Reached`。
    public static func isTargetOrAttached<Node>(
        _ window: Node,
        to targetWindow: Node,
        cutoff: ScanCutoff = .never,
        isSameElement: (Node, Node) -> Bool,
        parent: (Node) -> Node?
    ) throws -> Bool {
        if isSameElement(window, targetWindow) {
            return true
        }
        try cutoff.throwIfReached()
        guard let windowParent = parent(window) else { return false }
        return isSameElement(windowParent, targetWindow)
    }
}
