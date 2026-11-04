import Foundation
import CoreGraphics
import Testing
import OpenPathCore

@Suite("SavePanelLocationSearch: 絶対パスを根拠に保存先を確認する")
struct SavePanelLocationSearchTests {
    /// 保存パネルの既知の表示だけを再現する。行の祖先は子リストとは別の AXDisclosedByRow とする。
    private final class Node {
        let role: String
        var identifier: String?
        var subrole: String?
        var value: String?
        var path: String?
        var level: Int?
        var ancestor: Node?
        var titleElement: Node?
        var children: [Node]
        var rows: [Node] = []

        init(_ role: String, identifier: String? = nil, children: [Node] = []) {
            self.role = role
            self.identifier = identifier
            self.children = children
        }

        static func row(_ path: String, level: Int = 0, ancestor: Node? = nil) -> Node {
            let name = Node("AXTextField")
            name.path = path
            let cell = Node("AXCell", children: [Node("AXImage"), name])
            cell.titleElement = name
            let row = Node("AXRow", children: [cell])
            row.level = level
            row.ancestor = ancestor
            return row
        }

        static func header() -> Node {
            let header = Node("AXRow", children: [Node("AXCell", children: [Node("AXStaticText")])])
            header.level = 0
            return header
        }

        static func search(_ text: String? = "") -> Node {
            let field = Node("AXTextField", identifier: "Search")
            field.subrole = "AXSearchField"
            field.value = text
            return field
        }

        static func list(_ rows: [Node]) -> Node {
            let list = Node("AXOutline", identifier: "ListView")
            list.rows = rows
            // 子にも全行が返る実際の outline を再現する。コンテナ走査はここへ潜ってはいけない。
            list.children = rows
            return list
        }

        static func panel(_ rows: [Node], controls: [Node] = [Node.search()]) -> Node {
            let sidebar = Node("AXOutline", identifier: "sidebar")
            sidebar.rows = [.row("/wrong/sidebar/item")]
            sidebar.children = sidebar.rows
            return Node("AXWindow", identifier: "save-panel", children: [sidebar, .list(rows)] + controls)
        }
    }

    /// 訪問回数と配列取得範囲を記録する。全件を返す children / visibleRows は本検証では使わない。
    private final class Reader: PanelTreeReader {
        let counter = AXOperationCounter()
        var rowReadLimits: [Int] = []
        func read<T>(_ value: T) -> T { counter.record(); return value }
        func role(of node: Node) throws -> String? { read(node.role) }
        func subrole(of node: Node) throws -> String? { read(node.subrole) }
        func identifier(of node: Node) throws -> String? { read(node.identifier) }
        func title(of node: Node) throws -> String? { read(nil) }
        func accessibilityDescription(of node: Node) throws -> String? { read(nil) }
        func children(of node: Node) throws -> [Node] { Issue.record("Unbounded children must not be read"); return [] }
        func frame(of node: Node) throws -> CGRect? { read(nil) }
        func visibleRows(of node: Node) throws -> [Node] { Issue.record("Visible-only rows must not be evidence"); return [] }
        func visibleChildren(of node: Node) throws -> [Node] { [] }
        func columns(of node: Node) throws -> [Node] { [] }
        func titleElement(of node: Node) throws -> Node? { read(node.titleElement) }
        func url(of node: Node) throws -> URL? { read(nil) }
        func isEnabled(of node: Node) throws -> Bool? { read(nil) }
        func textOpacity(of node: Node) throws -> Double? { read(nil) }
        func itemCount(_ attribute: PanelTreeItemsAttribute, of node: Node) throws -> Int {
            read(attribute == .rows ? node.rows.count : node.children.count)
        }
        func items(_ attribute: PanelTreeItemsAttribute, of node: Node, in range: Range<Int>) throws -> [Node] {
            counter.record()
            if attribute == .rows { rowReadLimits.append(range.count) }
            let items = attribute == .rows ? node.rows : node.children
            return Array(items.dropFirst(range.lowerBound).prefix(range.count))
        }
    }

    private func path(_ root: Node, reader: Reader = Reader(), cutoff: ScanCutoff = .never) throws -> String? {
        try SavePanelLocationSearch.path(
            in: root, reader: reader, cutoff: cutoff,
            boundedChildren: { node, limit in
                let result = try reader.items(.children, of: node, in: 0..<(limit + 1))
                return result.count <= limit ? result : nil
            },
            value: { reader.read($0.value) },
            disclosureLevel: { reader.read($0.level) },
            disclosedByRow: { reader.read($0.ancestor) },
            itemPath: { reader.read($0.path) }
        )
    }

    @Test("名前・言語に依存せず、保存パネル直下の項目 URL の親を返す")
    func exactParentFromNativeList() throws {
        let panel = Node.panel([.row("/example/資料/one.txt"), .row("/example/資料/link-to-other-folder/")])
        #expect(try path(panel) == "/example/資料")
    }

    @Test("macOS の静的見出しに所属する level 1 の直下項目を扱う")
    func groupedNativeHeader() throws {
        let header = Node.header()
        let panel = Node.panel([header, .row("/example/current/child", level: 1, ancestor: header)])
        #expect(try path(panel) == "/example/current")
    }

    @Test("ホストのシート内の save-panel だけを調べ、ホストの検索欄や sidebar を無視する")
    func isolatesSavePanelSheet() throws {
        let panel = Node.panel([.row("/example/current/child")])
        panel.identifier = "save-panel"
        let host = Node("AXWindow", children: [Node.search("unrelated host search"), panel])
        #expect(try path(host) == "/example/current")
    }

    @Test("開くパネル・未知の一覧・compact・空・複数のパネルは確認不能にする")
    func unsupportedPanelsHaveNoProof() throws {
        let open = Node.panel([.row("/example/current/child")])
        open.identifier = "open-panel"
        #expect(try path(open) == nil)
        let unknown = Node.panel([.row("/example/current/child")])
        unknown.children[1].identifier = "UnknownList"
        #expect(try path(unknown) == nil)
        #expect(try path(Node("AXWindow", identifier: "save-panel", children: [Node.search()])) == nil)
        #expect(try path(Node.panel([])) == nil)
        let host = Node("AXWindow", children: [Node.panel([.row("/a/one")]), Node.panel([.row("/b/two")])])
        #expect(try path(host) == nil)
    }

    @Test("検索中・検索状態を読めない・検索欄なし・複数の検索欄では確認不能にする")
    func requiresExactlyOneKnownEmptySearch() throws {
        for controls in [[Node.search("query")], [Node.search(nil)], [], [Node.search(), Node.search()]] {
            #expect(try path(Node.panel([.row("/example/current/child")], controls: controls)) == nil)
        }
    }

    @Test("移動先シートなどが重なっている場合や複数の一覧がある場合は確認不能")
    func rejectsOverlaidSheetAndAmbiguousLists() throws {
        let overlay = Node.panel([.row("/a/one")], controls: [Node.search(), Node("AXSheet")])
        #expect(try path(overlay) == nil)
        let multiple = Node.panel([.row("/a/one")], controls: [Node.search(), Node.list([.row("/a/two")])])
        #expect(try path(multiple) == nil)
    }

    @Test("フォルダを展開した子孫行を現在地の根拠に使わない")
    func excludesExpandedDescendants() throws {
        let directory = Node.row("/example/current/folder")
        let descendant = Node.row("/example/current/folder/deep", level: 1, ancestor: directory)
        #expect(try path(Node.panel([directory, descendant])) == "/example/current")
        #expect(try path(Node.panel([descendant])) == nil)
        let header = Node.header()
        let root = Node.row("/example/current/folder", level: 1, ancestor: header)
        let nested = Node.row("/example/current/folder/deep", level: 2, ancestor: root)
        #expect(try path(Node.panel([header, root, nested])) == "/example/current")
    }

    @Test("親の名前欄を読めない場合や未知の disclosure level を見出しと推測しない")
    func doesNotGuessUnknownAncestors() throws {
        let ancestor = Node.row("/example/current/folder")
        ancestor.children[0].titleElement?.path = nil
        #expect(try path(Node.panel([.row("/example/current/folder/deep", level: 1, ancestor: ancestor)])) == nil)
        let unknown = Node.row("/example/current/child")
        unknown.level = nil
        #expect(try path(Node.panel([unknown])) == nil)
    }

    @Test("項目 URL の親が一致しない場合は一方を選ばず確認不能にする")
    func rejectsConflictingParents() throws {
        #expect(try path(Node.panel([.row("/example/one/child"), .row("/example/two/child")])) == nil)
    }

    @Test("不正なパス・URL を読めない項目は確認不能", arguments: ["relative", "/bad\0path", "/"])
    func rejectsInvalidItemPaths(_ itemPath: String) throws {
        #expect(try path(Node.panel([.row(itemPath)])) == nil)
    }

    @Test("配列転送の上限を守り、部分的なコンテナ探索では現在地を推測しない")
    func boundsRowsAndContainers() throws {
        let reader = Reader()
        let panel = Node.panel((0..<20).map { .row("/example/current/\($0)") })
        #expect(try path(panel, reader: reader) == "/example/current")
        #expect(reader.rowReadLimits == [8])
        let crowded = Node.panel([.row("/example/current/child")])
        crowded.children += (0..<41).map { _ in Node("AXGroup") }
        #expect(try path(crowded) == nil)
        var deep = Node.panel([.row("/example/current/child")])
        for _ in 0..<10 { deep = Node("AXGroup", children: [deep]) }
        #expect(try path(deep) == nil)
    }

    /// 期限がどの読み取りで来ても、その後の AX 操作や部分結果の返却が発生しないことを確かめる。
    @Test("各読み取りの前後で cutoff を確認する")
    func respectsCutoffBeforeEveryRead() throws {
        let panel = Node.panel([.row("/example/current/child")])
        let full = Reader()
        #expect(try path(panel, reader: full) == "/example/current")
        for limit in 0...full.counter.value {
            let reader = Reader()
            #expect(throws: ScanCutoff.Reached.self) {
                try path(panel, reader: reader, cutoff: reader.counter.cutoff(afterOperations: limit))
            }
            #expect(reader.counter.value == limit)
        }
    }
}
