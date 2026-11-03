import Foundation

/// 標準の save-panel の既知のリスト表示だけから、表示中の保存先の絶対パスを読む。
/// 表示名・移動先シートの入力値は根拠にしない。空・検索中・未対応の表示形式は nil。
public enum SavePanelLocationSearch {
    private static let maximumDepth = 8
    private static let maximumNodes = 120
    private static let maximumChildren = 40
    private static let rowLimit = 8
    private static let fileListRoles: Set<String> = ["AXOutline", "AXTable", "AXBrowser", "AXCollectionList", "AXList"]

    /// 読み取りは cutoff の直前チェックと固定上限で制限する。最初の最大 8 行から、直下の項目の親を照合する。
    /// - Parameters:
    ///   - value: 検索欄の値。nil は検索していないと推測せず、確認不能にする。
    ///   - disclosureLevel: AXOutline の行の AXDisclosureLevel。
    ///   - disclosedByRow: 行の AXDisclosedByRow。展開したフォルダの子孫を根拠から外すために使う。
    ///   - itemPath: 名前要素の AXURL から得た絶対パス。file-reference URL のみ解決し、項目の symlink は解決しないこと。
    /// - Returns: 一意に読めた保存先の絶対パス。別の表示形式・不完全な探索・証拠不足なら nil。
    /// - Throws: cutoff と reader の読み取り失敗を伝播し、呼び出し側に成功と誤認させない。
    public static func path<Reader: PanelTreeReader>(
        in root: Reader.Node,
        reader: Reader,
        cutoff: ScanCutoff = .never,
        boundedChildren: (Reader.Node, Int) throws -> [Reader.Node]?,
        value: (Reader.Node) throws -> String?,
        disclosureLevel: (Reader.Node) throws -> Int?,
        disclosedByRow: (Reader.Node) throws -> Reader.Node?,
        itemPath: (Reader.Node) throws -> String?
    ) throws -> String? {
        /// 各 AX 操作の前後で期限を確認する。最後の読み取り中に期限を超えた場合も結果を使わない。
        func read<T>(_ operation: () throws -> T) throws -> T {
            try cutoff.throwIfReached()
            let result = try operation()
            try cutoff.throwIfReached()
            return result
        }

        /// 全件転送を避け、範囲内で全ての子を読めたときだけ返す。
        func children(_ node: Reader.Node) throws -> [Reader.Node]? {
            try read { try boundedChildren(node, maximumChildren) }
        }

        /// ファイル一覧の内部には潜らず、上限内で完全に調べたコンテナだけを返す。
        func containers(in start: Reader.Node, stopAtSavePanel: Bool) throws -> [Reader.Node]? {
            var queue: [(node: Reader.Node, depth: Int)] = [(start, 0)]
            var head = 0
            var nodes: [Reader.Node] = []
            while head < queue.count {
                guard head < maximumNodes else { return nil }
                let entry = queue[head]
                head += 1
                nodes.append(entry.node)
                guard let role = try read({ try reader.role(of: entry.node) }) else { return nil }
                if stopAtSavePanel,
                   try read({ try reader.identifier(of: entry.node) }) == "save-panel" { continue }
                let leafRoles: Set<String> = ["AXButton", "AXTextField", "AXStaticText", "AXImage", "AXDisclosureTriangle", "AXPopUpButton", "AXMenuButton", "AXScrollBar", "AXSplitter", "AXValueIndicator"]
                if fileListRoles.contains(role) || leafRoles.contains(role) || role == "AXMenu" { continue }
                guard let next = try children(entry.node) else { return nil }
                if !next.isEmpty, entry.depth >= maximumDepth { return nil }
                queue += next.map { ($0, entry.depth + 1) }
                guard queue.count <= maximumNodes else { return nil }
            }
            return nodes
        }

        guard let outer = try containers(in: root, stopAtSavePanel: true) else { return nil }
        var panels: [Reader.Node] = []
        for node in outer {
            let role = try read { try reader.role(of: node) }
            guard role == "AXWindow" || role == "AXSheet" else { continue }
            if try read({ try reader.identifier(of: node) }) == "save-panel" { panels.append(node) }
        }
        guard panels.count == 1, let panel = panels.first,
              let controls = try containers(in: panel, stopAtSavePanel: false) else { return nil }
        var lists: [Reader.Node] = []
        var searchCount = 0
        for (index, node) in controls.enumerated() {
            let role = try read { try reader.role(of: node) }
            let identifier = try read { try reader.identifier(of: node) }
            if index > 0, role == "AXSheet" || role == "AXWindow" { return nil }
            if role == "AXBrowser" || role == "AXCollectionList" || role == "AXMenu" { return nil }
            if role == "AXTextField" {
                let subrole = try read { try reader.subrole(of: node) }
                if identifier == "Search" || subrole == "AXSearchField" {
                    guard let text = try read({ try value(node) }), text.isEmpty else { return nil }
                    searchCount += 1
                }
            }
            if role == "AXOutline", identifier == "ListView" { lists.append(node) }
        }
        guard searchCount == 1, lists.count == 1, let list = lists.first else { return nil }
        let count = try read { try reader.itemCount(.rows, of: list) }
        guard count > 0 else { return nil }
        let rows = try read { try reader.items(.rows, of: list, in: 0..<min(count, rowLimit)) }
        guard rows.count == min(count, rowLimit) else { return nil }

        /// macOS の list view は、名前セルの AXTitleUIElement にファイル URL を持つ。
        func nameElement(in row: Reader.Node) throws -> Reader.Node? {
            guard let cells = try children(row), let first = cells.first,
                  try read({ try reader.role(of: first) }) == "AXCell" else { return nil }
            return try read { try reader.titleElement(of: first) }
        }

        /// Level 1 の親が静的な見出し行であることを確認する。フォルダの名前欄がある親は受け入れない。
        func isHeader(_ row: Reader.Node) throws -> Bool {
            guard try read({ try reader.role(of: row) }) == "AXRow",
                  try read({ try disclosureLevel(row) }) == 0,
                  try read({ try disclosedByRow(row) }) == nil,
                  let cells = try children(row), let first = cells.first,
                  try read({ try reader.role(of: first) }) == "AXCell",
                  let labels = try children(first), !labels.isEmpty else { return false }
            var hasText = false
            for label in labels {
                let role = try read { try reader.role(of: label) }
                guard role == "AXStaticText" || role == "AXImage" else { return false }
                hasText = hasText || role == "AXStaticText"
            }
            return hasText
        }

        var parentPath: String?
        for row in rows {
            guard try read({ try reader.role(of: row) }) == "AXRow",
                  let level = try read({ try disclosureLevel(row) }) else { return nil }
            // 0: 見出しを持たない直下行、1: 静的な見出しの配下。2 以上はフォルダ展開の子孫なので使わない。
            guard level == 0 || level == 1 else { continue }
            guard let name = try nameElement(in: row) else {
                guard try isHeader(row) else { return nil }
                continue
            }
            let nameRole = try read { try reader.role(of: name) }
            if nameRole == "AXStaticText", try isHeader(row) { continue }
            guard nameRole == "AXTextField" else { return nil }
            let ancestor = try read { try disclosedByRow(row) }
            if level == 0 {
                guard ancestor == nil else { return nil }
            } else {
                guard let ancestor, try isHeader(ancestor) else { continue }
            }
            guard let path = try read({ try itemPath(name) }), path.hasPrefix("/"), !path.contains("\0"),
                  let normalized = RootPathResolver(homeDirectory: "").resolve(path), normalized != "/" else { return nil }
            let parent = (normalized as NSString).deletingLastPathComponent
            if let parentPath, parentPath != parent { return nil }
            parentPath = parent
        }
        return parentPath
    }
}
