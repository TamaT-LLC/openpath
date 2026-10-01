import Foundation

/// 入力欄を移動先シートの入力欄とみなした手掛かり（`GoToFieldSearch` の選ぶ順）。
public enum GoToFieldEvidence: String, Equatable, Sendable {
    /// AXIdentifier が移動先シートの入力欄のもの（macOS 13 以降の移動先シート）。移動先シートの入力欄と言い切れる
    case pathFieldIdentifier
    /// 「移動」/「Go」ボタンと同じシートにある（旧来の移動先シート）
    case goButton
    /// placeholder がパスの入力欄を示す
    case placeholder
}

/// 移動先シートの入力欄と、確定に押すボタン・候補リスト（DSN-001 §3.2 ステップ 1, 3）。
public struct GoToFieldMatch<Node> {
    public let field: Node
    /// 入力欄と同じシートにある「移動」/「Go」ボタン。無ければ Return で確定する。
    public let goButton: Node?
    /// 入力欄と同じシートにある候補リスト（AXTable）。macOS 13 以降の移動先シートにある。
    public let suggestionList: Node?
    /// 入力欄を選んだ手掛かり。
    public let evidence: GoToFieldEvidence

    public init(field: Node, goButton: Node?, suggestionList: Node? = nil, evidence: GoToFieldEvidence) {
        self.field = field
        self.goButton = goButton
        self.suggestionList = suggestionList
        self.evidence = evidence
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
    ///   - identifier: 起点（パネルかどうかを見るため）と入力欄にだけ呼ぶ。
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
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, identifier: identifier, children: children
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
            return containers.match(for: field, evidence: .pathFieldIdentifier)
        }
        if let field = fields.last(where: { containers.goButtons[$0.element.container.id] != nil })?.element {
            return containers.match(for: field, evidence: .goButton)
        }
        for field in fields.reversed().map(\.element) {
            try cutoff.throwIfReached()
            if let text = placeholder(field.node), GoToSheetScan.isPathFieldPlaceholder(text) {
                return containers.match(for: field, evidence: .placeholder)
            }
        }
        return nil
    }
}

/// シート（所属先）ごとの「移動」ボタンと候補リスト。
private struct ContainerControls<Node> {
    var goButtons: [Int: Node] = [:]
    var suggestionLists: [Int: Node] = [:]

    func match(for field: PanelTreeTraversal.Element<Node>, evidence: GoToFieldEvidence) -> GoToFieldMatch<Node> {
        let containerID = field.container.id
        return GoToFieldMatch(
            field: field.node,
            goButton: goButtons[containerID],
            suggestionList: suggestionLists[containerID],
            evidence: evidence
        )
    }
}

/// 確定ボタンを何で特定したか（debug ログ用）。
public enum OpenButtonIdentification: String, Equatable, Sendable {
    /// 表題が確定ボタンの表題（DSN-001 §2.2）だった
    case title
    /// パネル（またはシート）の既定ボタン（AXDefaultButton）だった
    case defaultButton
}

/// 見つけた確定ボタンと、その特定のしかた。
public struct OpenButtonMatch<Node> {
    public let button: Node
    public let identification: OpenButtonIdentification

    public init(button: Node, identification: OpenButtonIdentification) {
        self.button = button
        self.identification = identification
    }
}

extension OpenButtonMatch: Equatable where Node: Equatable {}

/// auto_confirm で押す、パネルの確定ボタン（「開く」等）を探す（DSN-001 §3.1 ステップ 8）。
///
/// パネル（`PanelTreeTraversal` の isInPanel）の中から、次の順で選ぶ。
/// 1. シートの中のボタンのうち、表題が確定ボタンの表題（パネル判定と同じ `OpenPanelCriteria.isConfirmButtonTitle`）のもの
/// 2. シートの既定ボタン（AXDefaultButton）
/// 3. 起点（パネルそのものとみなした場合）のボタンのうち、表題が確定ボタンの表題のもの
/// 4. 起点（パネルそのものとみなした場合）の既定ボタン
///
/// シートの中を先に調べるのは、パネルがシートとして付いたダイアログで、ホスト側の「追加」等を押さないため。
/// 既定ボタンは、独自の表題（「読み込む」「フォルダーを開く」等）の確定ボタンを特定するために使う（Issue #89）。
/// NSOpenPanel の既定ボタンは確定ボタン（AXIdentifier `OKButton`）で、表題が独自でも変わらない（macOS 27 の自プロセスのパネルで確認）。
/// 閉じかけの移動先シートなど別のシートの既定ボタンを押さないよう、確定ボタンでない表題（キャンセル・新規フォルダ・「移動」）の
/// 既定ボタンは選ばない。パネルでない通常のウィンドウ（ホストのウィンドウ）の既定ボタンは読まない。
public enum OpenButtonSearch {
    /// 既定ボタンでも押さない表題。前後の空白を除いて比べる。
    static let nonConfirmTitles = Set(["キャンセル", "Cancel", "新規フォルダ", "New Folder"])
        .union(GoToFieldSearch.goButtonTitles)

    /// - Parameters:
    ///   - search: 探索の上限。既定は DSN-001 §2.2 と同じ深さ 6・400 要素。
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - subrole: 起点にだけ呼ぶ。
    ///   - identifier: 起点にだけ呼ぶ（ロール・サブロールでパネルと分からないとき）。
    ///   - title: ボタンと、既定ボタンにだけ呼ぶ。
    ///   - defaultButton: シートと、パネルそのものとみなした起点にだけ呼ぶ（AXDefaultButton）。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func locate<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        identifier: (Node) -> String?,
        title: (Node) -> String?,
        defaultButton: (Node) -> Node?,
        children: (Node) -> [Node]
    ) throws -> OpenButtonMatch<Node>? {
        let traversal = try PanelTreeTraversal.traverse(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, identifier: identifier, children: children
        )
        let buttons = traversal.elements.filter { $0.container.isInPanel && $0.role == PanelTreeTraversal.buttonRole }
        // シートは、ホストのウィンドウの子でもパネル（またはその上に重なったシート）として扱う
        let sheets = traversal.elements.filter { $0.role == GoToSheetScan.sheetRole }.map(\.node)
        if let match = try firstMatch(
            buttons: buttons.filter(\.container.isSheet).map(\.node),
            containers: sheets,
            cutoff: cutoff,
            title: title,
            defaultButton: defaultButton
        ) {
            return match
        }
        return try firstMatch(
            buttons: buttons.filter { !$0.container.isSheet }.map(\.node),
            containers: traversal.isRootPanel ? [root] : [],
            cutoff: cutoff,
            title: title,
            defaultButton: defaultButton
        )
    }

    /// buttons の表題を先に、containers（シート・起点）の既定ボタンを後に調べる。
    private static func firstMatch<Node>(
        buttons: [Node],
        containers: [Node],
        cutoff: ScanCutoff,
        title: (Node) -> String?,
        defaultButton: (Node) -> Node?
    ) throws -> OpenButtonMatch<Node>? {
        for button in buttons {
            try cutoff.throwIfReached()
            if let buttonTitle = title(button), OpenPanelCriteria.isConfirmButtonTitle(buttonTitle) {
                return OpenButtonMatch(button: button, identification: .title)
            }
        }
        for container in containers {
            try cutoff.throwIfReached()
            guard let candidate = defaultButton(container) else { continue }
            try cutoff.throwIfReached()
            if isAcceptableDefaultButtonTitle(title(candidate)) {
                return OpenButtonMatch(button: candidate, identification: .defaultButton)
            }
        }
        return nil
    }

    /// 既定ボタンを確定ボタンとして押してよいか（確定ボタンでない表題なら押さない）。
    static func isAcceptableDefaultButtonTitle(_ title: String?) -> Bool {
        guard let title else { return true }
        return !nonConfirmTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
