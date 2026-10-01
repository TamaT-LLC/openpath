/// 副方式と auto_confirm で操作する要素を探すための、パネルの AX ツリーの走査（DSN-001 §3.1 ステップ 8, §3.2）。
///
/// 各要素に「どのシートに属するか」と「パネルの中か」を付けて返す。
/// 起点（フォーカス中のウィンドウ）が通常のウィンドウの場合、パネルはそのシートとして付いている。
/// パネルが閉じた後にホストアプリの入力欄やボタンを操作しないよう、シートの外の要素はパネルの外として扱う。
///
/// 起点そのものをパネルとみなす条件は、パネル判定（DSN-001 §2.2 の条件 1、`OpenPanelCriteria.isPanelCandidate`）と同じにする。
/// - ダイアログ（サブロール AXDialog）: `runModal` のパネル（`choose folder` など）
/// - シート（ロール AXSheet。サブロールは無い）: シートとして付いたパネルや、注入の前から開いていた移動先シートが、
///   フォーカス中のウィンドウとして返る（macOS 27 の自プロセスのパネルで確認、Issue #89 / #95）
/// - AXIdentifier が `open-panel` のウィンドウ: 非モーダルのパネル（サブロールは AXStandardWindow、Issue #83 / #89）
///
/// 以前はサブロールだけで判定していたため、シート型・非モーダルのパネルでは起点の要素（「開く」など）がパネルの外になり、
/// auto_confirm の「開く」が見つからなかった（Issue #89）。
enum PanelTreeTraversal {
    static let buttonRole = "AXButton"

    /// 要素の所属先。最も近い祖先の AXSheet、無ければ起点のウィンドウ。
    struct Container: Equatable {
        /// 起点のウィンドウは 0、シートは見つけた順に 1 から。
        let id: Int
        /// パネル（またはその上に重なったシート）の中か。
        let isInPanel: Bool

        var isSheet: Bool {
            id != PanelTreeTraversal.rootContainerID
        }
    }

    struct Element<Node> {
        let node: Node
        let role: String?
        let container: Container
        /// 子の所属先。自身がシートなら自身。
        let childContainer: Container
    }

    static let rootContainerID = 0

    /// root の子孫を幅優先で返す。
    /// - Parameters:
    ///   - cutoff: 打ち切り条件。subrole / identifier / children / role の各呼び出し（AX 操作）の直前に確かめる。
    ///   - subrole: 起点のサブロール。起点にだけ呼ぶ。
    ///   - identifier: 起点の AXIdentifier。起点にだけ呼ぶ。
    ///   - role: 要素のロール。1 要素につき 1 回だけ呼ぶ。
    ///   - children: 要素の子。ファイル一覧など `GoToSheetScan.prunedRoles` の要素には呼ばない。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    static func elements<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch,
        cutoff: ScanCutoff,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> [Element<Node>] {
        try traverse(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, identifier: identifier, children: children
        ).elements
    }

    /// `elements(in:…)` と同じ走査で、起点をパネルそのものとみなしたかも返す。
    static func traverse<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch,
        cutoff: ScanCutoff,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> (isRootPanel: Bool, elements: [Element<Node>]) {
        let rootKind = try classifyRoot(root, cutoff: cutoff, role: role, subrole: subrole, identifier: identifier)
        let rootContainer = Container(id: rootContainerID, isInPanel: rootKind.isPanel)
        var nextSheetID = rootContainerID + 1
        let elements = try search.descendants(
            of: Element(node: root, role: rootKind.role, container: rootContainer, childContainer: rootContainer),
            children: { parent in
                if let parentRole = parent.role, GoToSheetScan.prunedRoles.contains(parentRole) {
                    return []
                }
                try cutoff.throwIfReached()
                return try children(parent.node).map { child in
                    try cutoff.throwIfReached()
                    let childRole = role(child)
                    var childContainer = parent.childContainer
                    if childRole == GoToSheetScan.sheetRole {
                        childContainer = Container(id: nextSheetID, isInPanel: true)
                        nextSheetID += 1
                    }
                    return Element(node: child, role: childRole, container: parent.childContainer, childContainer: childContainer)
                }
            }
        )
        return (rootKind.isPanel, elements)
    }

    /// 起点をパネルそのものとみなすか。AXIdentifier は、ロール・サブロールでパネルと分からないときだけ読む。
    /// - Returns: 起点のロールと、パネルとみなすか。
    private static func classifyRoot<Node>(
        _ root: Node,
        cutoff: ScanCutoff,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        identifier: (Node) -> String?
    ) throws -> (role: String?, isPanel: Bool) {
        try cutoff.throwIfReached()
        let rootRole = role(root)
        try cutoff.throwIfReached()
        let rootSubrole = subrole(root)
        if OpenPanelCriteria.isPanelCandidate(role: rootRole, subrole: rootSubrole) {
            return (rootRole, true)
        }
        try cutoff.throwIfReached()
        let rootIdentifier = identifier(root)
        return (rootRole, OpenPanelCriteria.isPanelCandidate(role: rootRole, subrole: rootSubrole, identifier: rootIdentifier))
    }
}
