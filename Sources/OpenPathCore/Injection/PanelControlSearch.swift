/// 移動先シートの入力欄と、確定に押すボタン・候補リスト（DSN-001 §3.2 ステップ 1, 3）。
public struct GoToFieldMatch<Node> {
    public let field: Node
    /// 入力欄と同じシートにある「移動」/「Go」ボタン。無ければ Return で確定する。
    public let goButton: Node?
    /// 入力欄と同じシートにある候補リスト（AXTable）。macOS 13 以降の移動先シートにある。
    public let suggestionList: Node?

    public init(field: Node, goButton: Node?, suggestionList: Node? = nil) {
        self.field = field
        self.goButton = goButton
        self.suggestionList = suggestionList
    }
}

extension GoToFieldMatch: Equatable where Node: Equatable {}

/// 移動先シートの入力欄を探す（副方式の DSN-001 §3.2 ステップ 1 と、主方式の確定前の確認）。
///
/// パネル（`PanelTreeTraversal` の isInPanel）の中の入力欄（AXTextField / AXComboBox、検索フィールドを除く）のうち、次の順で選ぶ。
/// 1. AXIdentifier が移動先シートの入力欄のもの（macOS 13 以降の移動先シート。placeholder も「移動」ボタンも無い。Issue #74）
/// 2. 「移動」/「Go」ボタンと同じシートにあるもの（旧来の移動先シート）
/// 3. placeholder がパスの入力欄を示すもの（主方式のシート判定と同じ語）
/// どれも複数あれば、後から重なった（深い）シートのものを選ぶ。どれにも当たらなければ移動先シートは無いとみなす。
/// パネルのツールバーの検索フィールドやアクセサリの入力欄を移動先と取り違えないよう、手掛かりの無い入力欄は選ばない。
public enum GoToFieldSearch {
    static let goButtonTitles: Set<String> = ["移動", "Go"]
    static let searchFieldSubrole = "AXSearchField"
    /// macOS 13 以降の移動先シート（FinderKit）の入力欄の AXIdentifier（macOS 27 で確認、Issue #74）。
    static let pathFieldIdentifier = "PathTextField"
    /// 移動先シートの候補リストのロール。
    static let suggestionListRole = "AXTable"

    /// - Parameters:
    ///   - search: 探索の上限。既定は DSN-001 §2.2 と同じ深さ 6・400 要素。
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - subrole: 起点と入力欄にだけ呼ぶ。
    ///   - title: ボタンにだけ呼ぶ。
    ///   - identifier: 入力欄にだけ呼ぶ。
    ///   - placeholder: 手掛かり（AXIdentifier・「移動」ボタン）の無い入力欄にだけ呼ぶ。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func locate<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        title: (Node) -> String?,
        identifier: (Node) -> String?,
        placeholder: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> GoToFieldMatch<Node>? {
        let elements = try PanelTreeTraversal.elements(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, children: children
        )
        var containers = ContainerControls<Node>()
        var fields: [(element: PanelTreeTraversal.Element<Node>, isGoToField: Bool)] = []
        for element in elements where element.container.isInPanel {
            guard let elementRole = element.role else { continue }
            let containerID = element.container.id
            if elementRole == PanelTreeTraversal.buttonRole {
                guard containers.goButtons[containerID] == nil else { continue }
                try cutoff.throwIfReached()
                if let buttonTitle = title(element.node), goButtonTitles.contains(buttonTitle) {
                    containers.goButtons[containerID] = element.node
                }
            } else if elementRole == suggestionListRole {
                if containers.suggestionLists[containerID] == nil {
                    containers.suggestionLists[containerID] = element.node
                }
            } else if GoToSheetScan.pathFieldRoles.contains(elementRole) {
                try cutoff.throwIfReached()
                guard subrole(element.node) != searchFieldSubrole else { continue }
                try cutoff.throwIfReached()
                fields.append((element, identifier(element.node) == pathFieldIdentifier))
            }
        }

        // 幅優先の順のため、後ろほど深い（後から重なった）シートの要素
        if let field = fields.last(where: \.isGoToField)?.element {
            return containers.match(for: field)
        }
        if let field = fields.last(where: { containers.goButtons[$0.element.container.id] != nil })?.element {
            return containers.match(for: field)
        }
        for field in fields.reversed().map(\.element) {
            try cutoff.throwIfReached()
            if let text = placeholder(field.node), GoToSheetScan.isPathFieldPlaceholder(text) {
                return containers.match(for: field)
            }
        }
        return nil
    }
}

/// シート（所属先）ごとの「移動」ボタンと候補リスト。
private struct ContainerControls<Node> {
    var goButtons: [Int: Node] = [:]
    var suggestionLists: [Int: Node] = [:]

    func match(for field: PanelTreeTraversal.Element<Node>) -> GoToFieldMatch<Node> {
        let containerID = field.container.id
        return GoToFieldMatch(
            field: field.node,
            goButton: goButtons[containerID],
            suggestionList: suggestionLists[containerID]
        )
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
