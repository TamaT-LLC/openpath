/// 副方式で値をセットする入力欄と、確定に押すボタン（DSN-001 §3.2 ステップ 1, 3）。
public struct GoToFieldMatch<Node> {
    public let field: Node
    /// 入力欄と同じシートにある「移動」/「Go」ボタン。無ければ入力欄を確定する（kAXConfirmAction）。
    public let goButton: Node?

    public init(field: Node, goButton: Node?) {
        self.field = field
        self.goButton = goButton
    }
}

extension GoToFieldMatch: Equatable where Node: Equatable {}

/// 副方式で値をセットする、移動先シートの入力欄を探す（DSN-001 §3.2 ステップ 1）。
///
/// パネル（`PanelTreeTraversal` の isInPanel）の中の入力欄（AXTextField / AXComboBox、検索フィールドを除く）のうち、次の順で選ぶ。
/// 1. 「移動」/「Go」ボタンと同じシートにあるもの（旧来の移動先シート）
/// 2. placeholder がパスの入力欄を示すもの（主方式のシート判定と同じ語）
/// どちらも複数あれば、後から重なった（深い）シートのものを選ぶ。どれにも当たらなければ移動先シートは無いとみなす。
/// パネルのツールバーの検索フィールドやアクセサリの入力欄を移動先と取り違えないよう、手掛かりの無い入力欄は選ばない。
public enum GoToFieldSearch {
    static let goButtonTitles: Set<String> = ["移動", "Go"]
    static let searchFieldSubrole = "AXSearchField"

    /// - Parameters:
    ///   - search: 探索の上限。既定は DSN-001 §2.2 と同じ深さ 6・400 要素。
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - subrole: 起点と入力欄にだけ呼ぶ。
    ///   - title: ボタンにだけ呼ぶ。
    ///   - placeholder: 「移動」ボタンと組にならなかった入力欄にだけ呼ぶ。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func locate<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        title: (Node) -> String?,
        placeholder: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> GoToFieldMatch<Node>? {
        let elements = try PanelTreeTraversal.elements(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, children: children
        )
        var goButtonsByContainer: [Int: Node] = [:]
        var fields: [PanelTreeTraversal.Element<Node>] = []
        for element in elements where element.container.isInPanel {
            guard let elementRole = element.role else { continue }
            if elementRole == PanelTreeTraversal.buttonRole {
                guard goButtonsByContainer[element.container.id] == nil else { continue }
                try cutoff.throwIfReached()
                if let buttonTitle = title(element.node), goButtonTitles.contains(buttonTitle) {
                    goButtonsByContainer[element.container.id] = element.node
                }
            } else if GoToSheetScan.pathFieldRoles.contains(elementRole) {
                try cutoff.throwIfReached()
                if subrole(element.node) != searchFieldSubrole {
                    fields.append(element)
                }
            }
        }

        // 幅優先の順のため、後ろほど深い（後から重なった）シートの要素
        if let field = fields.last(where: { goButtonsByContainer[$0.container.id] != nil }) {
            return GoToFieldMatch(field: field.node, goButton: goButtonsByContainer[field.container.id])
        }
        for field in fields.reversed() {
            try cutoff.throwIfReached()
            if let text = placeholder(field.node), GoToSheetScan.isPathFieldPlaceholder(text) {
                return GoToFieldMatch(field: field.node, goButton: nil)
            }
        }
        return nil
    }
}

/// auto_confirm で押す、パネルの確定ボタン（「開く」等）を探す（DSN-001 §3.1 ステップ 8）。
///
/// パネル（`PanelTreeTraversal` の isInPanel）の中のボタンのうち、タイトルが DSN-001 §2.2 の確定ボタンのものを選ぶ。
/// シートの中のボタンを優先する。パネルがシートとして付いたダイアログで、ホスト側の「追加」等を押さないため。
public enum OpenButtonSearch {
    /// DSN-001 §2.2 のパネル判定と同じ確定ボタンのタイトル。
    static let confirmTitles: Set<String> = ["開く", "Open", "選択", "Choose", "追加", "Add"]

    /// - Parameters:
    ///   - search: 探索の上限。既定は DSN-001 §2.2 と同じ深さ 6・400 要素。
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - subrole: 起点にだけ呼ぶ。
    ///   - title: ボタンにだけ呼ぶ。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func locate<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        title: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> Node? {
        let buttons = try PanelTreeTraversal.elements(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, children: children
        ).filter { $0.container.isInPanel && $0.role == PanelTreeTraversal.buttonRole }

        let insideSheets = buttons.filter(\.container.isSheet)
        let outsideSheets = buttons.filter { !$0.container.isSheet }
        for button in insideSheets + outsideSheets {
            try cutoff.throwIfReached()
            if let buttonTitle = title(button.node), confirmTitles.contains(buttonTitle) {
                return button.node
            }
        }
        return nil
    }
}
