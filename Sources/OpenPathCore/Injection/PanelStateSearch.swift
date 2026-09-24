/// 移動先シートの候補リストで選ばれている行から、その候補が指すパスを読む（Issue #74）。
///
/// macOS 27 の移動先シートでは、候補の行（AXRow > AXCell）の下の AXList が、候補のパスを AXIdentifier に持つ
/// （見出しの行「Go to:」は AXStaticText だけで AXList を持たない）。パスとして読めるのは `/` で始まるものだけにする。
public enum GoToSuggestionSearch {
    static let pathListRole = "AXList"
    /// 行から AXList までの深さ（AXRow > AXCell > AXList）に余裕を持たせた上限。
    static let maxDepth = 3

    /// - Parameters:
    ///   - row: 選ばれている行。
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - identifier: AXList にだけ呼ぶ。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func path<Node>(
        inSelectedRow row: Node,
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> String? {
        var level = [row]
        for _ in 0..<maxDepth {
            var next: [Node] = []
            for node in level {
                try cutoff.throwIfReached()
                for child in children(node) {
                    try cutoff.throwIfReached()
                    guard role(child) == pathListRole else {
                        next.append(child)
                        continue
                    }
                    try cutoff.throwIfReached()
                    if let path = identifier(child), path.hasPrefix("/") {
                        return path
                    }
                }
            }
            level = next
        }
        return nil
    }
}

/// パネルが表示している現在地（フォルダの表示名）を探す（Issue #74 の診断ログ用）。
///
/// macOS 27 の NSOpenPanel（FinderKit）では、ツールバーの場所のポップアップ（AXIdentifier `where popup`）の値が現在のフォルダの表示名。
/// 表示名はローカライズされる（「ライブラリ」等）ため、移動先の名前と一致しないことがある。診断のログにだけ使う。
public enum PanelLocationSearch {
    static let popUpButtonRole = "AXPopUpButton"
    static let locationPopUpIdentifier = "where popup"

    /// - Parameters:
    ///   - cutoff: 打ち切り条件。AX 操作（各クロージャの呼び出し）の直前に確かめる。
    ///   - identifier: ポップアップボタンにだけ呼ぶ。
    ///   - value: 場所のポップアップにだけ呼ぶ。
    /// - Returns: 場所のポップアップが見つからなければ nil。
    /// - Throws: 打ち切り条件に達したら、それ以降の AX 操作をせずに `ScanCutoff.Reached`。
    public static func displayedFolderName<Node>(
        in root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        identifier: (Node) -> String?,
        value: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> String? {
        let elements = try PanelTreeTraversal.elements(
            in: root, search: search, cutoff: cutoff, role: role, subrole: subrole, children: children
        )
        for element in elements where element.role == popUpButtonRole {
            try cutoff.throwIfReached()
            guard identifier(element.node) == locationPopUpIdentifier else { continue }
            try cutoff.throwIfReached()
            return value(element.node)
        }
        return nil
    }
}
