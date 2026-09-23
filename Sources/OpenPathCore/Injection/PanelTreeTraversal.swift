/// 副方式と auto_confirm で操作する要素を探すための、パネルの AX ツリーの走査（DSN-001 §3.1 ステップ 8, §3.2）。
///
/// 各要素に「どのシートに属するか」と「パネルの中か」を付けて返す。
/// 起点（フォーカス中のウィンドウ）が通常のウィンドウの場合、パネルはそのシートとして付いている。
/// パネルが閉じた後にホストアプリの入力欄やボタンを操作しないよう、シートの外の要素はパネルの外として扱う。
enum PanelTreeTraversal {
    static let buttonRole = "AXButton"
    /// パネルそのものとみなすウィンドウのサブロール（DSN-001 §2.2 のパネル判定と同じ）。
    static let panelWindowSubroles: Set<String> = ["AXDialog", "AXSheet"]

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
    ///   - cutoff: 打ち切り条件。subrole / children / role の各呼び出し（AX 操作）の直前に確かめる。
    ///   - subrole: 起点のサブロール。起点にだけ呼ぶ。
    ///   - role: 要素のロール。1 要素につき 1 回だけ呼ぶ。
    ///   - children: 要素の子。ファイル一覧など `GoToSheetScan.prunedRoles` の要素には呼ばない。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    static func elements<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch,
        cutoff: ScanCutoff,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> [Element<Node>] {
        try cutoff.throwIfReached()
        let isRootPanel = subrole(root).map(panelWindowSubroles.contains) ?? false
        let rootContainer = Container(id: rootContainerID, isInPanel: isRootPanel)
        var nextSheetID = rootContainerID + 1
        return try search.descendants(
            of: Element(node: root, role: nil, container: rootContainer, childContainer: rootContainer),
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
    }
}
