/// 移動先シートの出現判定に使う、AX ツリーの集計結果（DSN-001 §3.1 ステップ 4）。
///
/// DSN-001 の判定条件「パネルの子孫に AXSheet または placeholder にパスを示す語を含む入力欄が出現」を、
/// ⌘⇧G の送出前（基準）と後の集計の比較として扱う。送出前からあるシート（パネル自体がシートの場合）を誤認しないため。
/// AX から切り離し、要素の型と属性の読み方を呼び出し側から受け取ることでユニットテスト可能にしている。
public struct GoToSheetScan: Equatable, Sendable {
    /// ロール名は AX の定数（kAXSheetRole 等）と同じ文字列。Core に ApplicationServices を持ち込まないため文字列で持つ。
    static let sheetRole = "AXSheet"
    /// 旧来の移動先シートは入力欄がコンボボックスのため、両方を対象にする。
    static let pathFieldRoles: Set<String> = ["AXTextField", "AXComboBox"]
    /// 比較は小文字で行う。
    static let placeholderKeywords = ["パス", "path", "go to"]
    /// 行やセルが大量にあり移動先シートを含まない要素。中へ降りないことで AX の往復を減らす。
    static let prunedRoles: Set<String> = ["AXBrowser", "AXOutline", "AXTable", "AXList", "AXWebArea"]

    public let sheetCount: Int
    public let pathFieldCount: Int

    public init(sheetCount: Int, pathFieldCount: Int) {
        self.sheetCount = sheetCount
        self.pathFieldCount = pathFieldCount
    }

    /// 基準の時点からシートかパス入力欄が増えていれば、移動先シートが出たとみなす。
    public func indicatesSheetShown(since baseline: GoToSheetScan) -> Bool {
        sheetCount > baseline.sheetCount || pathFieldCount > baseline.pathFieldCount
    }

    /// placeholder がパスの入力欄を示すか（「パス」「Path」「Go to」を含むか。大文字小文字は区別しない）。
    public static func isPathFieldPlaceholder(_ placeholder: String) -> Bool {
        let lowercased = placeholder.lowercased()
        return placeholderKeywords.contains { lowercased.contains($0) }
    }

    /// root（パネルのウィンドウ）の子孫を幅優先で集計する。
    /// - Parameters:
    ///   - search: 探索の上限。既定は DSN-001 §2.2 と同じ深さ 6・400 要素。
    ///   - role: 要素のロール。1 要素につき 1 回だけ呼ぶ。
    ///   - children: 要素の子。ファイル一覧など `prunedRoles` の要素には呼ばない。
    ///   - placeholder: 入力欄の placeholder。入力欄のロールの要素にだけ呼ぶ。
    public static func scan<Node>(
        from root: Node,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch(),
        role: (Node) -> String?,
        children: (Node) -> [Node],
        placeholder: (Node) -> String?
    ) -> GoToSheetScan {
        // ロールの読み取り（AX の往復）を 1 要素 1 回にするため、子を列挙するときにロールも読んで組にする
        let rootElement = ScannedElement(node: root, role: nil)
        let matches = search.descendants(
            of: rootElement,
            children: { element in
                if let elementRole = element.role, prunedRoles.contains(elementRole) {
                    return []
                }
                return children(element.node).map { ScannedElement(node: $0, role: role($0)) }
            },
            where: { element in
                guard let elementRole = element.role else { return false }
                if elementRole == sheetRole {
                    return true
                }
                guard pathFieldRoles.contains(elementRole), let text = placeholder(element.node) else { return false }
                return isPathFieldPlaceholder(text)
            }
        )
        let sheetCount = matches.count(where: { $0.role == sheetRole })
        return GoToSheetScan(sheetCount: sheetCount, pathFieldCount: matches.count - sheetCount)
    }
}

/// 探索中の要素と、列挙時に読み取ったロールの組。
private struct ScannedElement<Node> {
    let node: Node
    let role: String?
}
