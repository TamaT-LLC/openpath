import Foundation

/// ファイル一覧の項目。
struct FileListItem {
    enum Kind {
        case directory
        case file
    }

    let name: String
    let kind: Kind
    /// パネルで選べる項目か。リスト表示・カラム表示では文字色（`textOpacity`）に、アイコン表示では AXEnabled に表れる
    var isSelectable = true
    /// 名前の文字色の不透明度。nil なら読めない（属性付き文字列を持たない要素など）
    var textOpacity: Double?
    /// 名前の要素の AXEnabled。FinderKit のリスト表示・カラム表示では、選べない行も true のまま。
    /// アイコン表示では、選べない項目（`isSelectable` が false）なら false にする。nil なら AXEnabled を持たない
    var isEnabled: Bool? = true
    /// 名前の要素が AXURL を持つか
    var hasURL = true

    static func directory(_ name: String) -> FileListItem {
        FileListItem(name: name, kind: .directory, textOpacity: FileListFixtures.normalTextOpacity)
    }

    /// 選べるファイル（通常の文字色）。
    static func file(_ name: String) -> FileListItem {
        FileListItem(name: name, kind: .file, textOpacity: FileListFixtures.normalTextOpacity)
    }

    /// 選べないファイル（淡い文字色）。フォルダのみのパネルのファイル行。
    static func dimmedFile(_ name: String) -> FileListItem {
        FileListItem(name: name, kind: .file, isSelectable: false, textOpacity: FileListFixtures.dimmedTextOpacity)
    }
}

/// NSOpenPanel のファイル一覧（FinderKit）の AX ツリー。macOS 26 のプロセス内パネル（NSUseRemoteSavePanel=NO）で
/// AX API から見えた構造を簡略化したもの。
enum FileListFixtures {
    /// 実測した名前の文字色の不透明度（ダークモード）。通常の行・選べない行
    static let normalTextOpacity = 0.847059
    static let dimmedTextOpacity = 0.247059

    static let fileListID = "file-list"

    /// 名前の要素（AXTextField）の id。
    static func nameID(_ name: String, in listID: String = fileListID) -> String {
        "\(listID)/name/\(name)"
    }

    /// 項目の URL。実機ではファイル参照 URL（file:///.file/id=...）で、ディレクトリは末尾が "/" になる。
    static func url(for item: FileListItem) -> URL {
        URL(
            filePath: "/.file/id=6571367.\(item.name)",
            directoryHint: item.kind == .directory ? .isDirectory : .notDirectory
        )
    }

    // MARK: - カラム表示

    /// カラム表示（AXBrowser）。AXColumns は左の列から順で、最後の列が今のフォルダ。
    /// - Parameters:
    ///   - ancestors: 今のフォルダより左の列（親フォルダ）の項目。
    ///   - hasPreviewColumn: ファイルを選んだときに右に出るプレビューの列（AXList を持たない）を付けるか。
    static func columnView(
        id: String = fileListID,
        ancestors: [[FileListItem]] = [[.directory("Users")]],
        items: [FileListItem],
        hasPreviewColumn: Bool = false
    ) -> StubNode {
        var columns = (ancestors + [items]).enumerated().map { index, columnItems in
            let columnID = "\(id)/column/\(index)"
            return StubNode(id: columnID, role: "AXScrollArea", children: [
                StubNode(role: "AXList", children: columnItems.map { browserItem($0, listID: columnID) }),
                StubNode(role: "AXScrollBar"),
            ])
        }
        if hasPreviewColumn {
            columns.append(StubNode(id: "\(id)/column/preview", role: "AXScrollArea", children: [
                StubNode(role: "AXGroup", children: [StubNode(role: "AXImage"), StubNode(role: "AXStaticText")]),
            ]))
        }
        return StubNode(
            id: id,
            role: "AXBrowser",
            children: [StubNode(role: "AXScrollArea", children: columns)],
            columnIDs: columns.compactMap(\.id)
        )
    }

    /// カラム表示の項目。AXGroup の AXTitleUIElement が名前の AXTextField。
    private static func browserItem(_ item: FileListItem, listID: String) -> StubNode {
        let nameElementID = nameID(item.name, in: listID)
        return StubNode(role: "AXGroup", children: [
            StubNode(role: "AXImage"),
            nameField(item, id: nameElementID),
        ], titleElementID: nameElementID)
    }

    // MARK: - リスト表示

    /// リスト表示（AXOutline）。先頭に並べ替えの見出しの行（名前の要素を持たない）があり、行の後に列と見出しが続く。
    static func listView(id: String = fileListID, role: String = "AXOutline", items: [FileListItem]) -> StubNode {
        let headingRow = StubNode(role: "AXRow", children: [
            StubNode(role: "AXCell", children: [
                StubNode(role: "AXStaticText", title: "名前"),
                StubNode(role: "AXStaticText", title: "種類"),
                StubNode(role: "AXImage"),
            ]),
        ])
        let rows = items.map { item in
            let nameElementID = nameID(item.name, in: id)
            var nameCellChildren = [StubNode(role: "AXImage"), nameField(item, id: nameElementID)]
            if item.kind == .directory {
                nameCellChildren.append(StubNode(role: "AXDisclosureTriangle"))
            }
            return StubNode(role: "AXRow", children: [
                StubNode(role: "AXCell", children: nameCellChildren, titleElementID: nameElementID),
                StubNode(role: "AXCell", children: [StubNode(role: "AXStaticText")]),
                StubNode(role: "AXCell", children: [StubNode(role: "AXStaticText")]),
            ])
        }
        let columns = (0..<3).map { _ in StubNode(role: "AXColumn") }
        return StubNode(id: id, role: role, children: [headingRow] + rows + columns + [StubNode(role: "AXGroup")])
    }

    // MARK: - アイコン表示

    /// アイコン表示（NSCollectionView）。ロールが AXList でサブロールが AXCollectionList。
    /// AXVisibleChildren はセクション（AXList / AXSectionList）で、セクションの AXVisibleChildren が項目（AXGroup）。
    /// 「グループ分け」を使うと、セクションが複数になる。
    static func iconView(id: String = fileListID, sections: [[FileListItem]]) -> StubNode {
        StubNode(id: id, role: "AXList", subrole: "AXCollectionList", description: "icon view", children: sections.map { items in
            StubNode(role: "AXList", subrole: "AXSectionList", children: items.map { iconItem($0, listID: id) })
        })
    }

    static func iconView(id: String = fileListID, items: [FileListItem]) -> StubNode {
        iconView(id: id, sections: [items])
    }

    /// アイコン表示の項目。AXGroup（AXTitleUIElement を持たない）の子の AXImage が、AXURL と AXEnabled を持つ。
    /// AXImage は文字列を持たないため文字色は読めず、選べない項目は AXEnabled が false になる。
    private static func iconItem(_ item: FileListItem, listID: String) -> StubNode {
        StubNode(role: "AXGroup", children: [
            StubNode(
                id: nameID(item.name, in: listID),
                role: "AXImage",
                description: item.name,
                url: item.hasURL ? url(for: item) : nil,
                isEnabled: item.isEnabled.map { $0 && item.isSelectable }
            ),
        ])
    }

    // MARK: - パネル

    /// FinderKit の開くパネルの中身。サイドバー（AXOutline）の後にファイル一覧が現れる。
    /// - Parameter sidebar: nil ならサイドバーを隠したパネル（⌃⌘S）。
    static func openPanelBody(
        fileList: StubNode,
        sidebar: StubNode? = FileListFixtures.sidebar(),
        confirmTitle: String = "開く"
    ) -> [StubNode] {
        let sidebarPane = sidebar.map { [StubNode(role: "AXScrollArea", children: [$0]), StubNode(role: "AXSplitter")] } ?? []
        return [
            StubNode(role: "AXSplitGroup", children: sidebarPane + [
                StubNode(role: "AXSplitGroup", children: [
                    fileList.role == "AXBrowser" ? fileList : StubNode(role: "AXScrollArea", children: [fileList]),
                ]),
            ]),
            StubNode(role: "AXGroup", children: [
                StubNode(role: "AXButton", description: "戻る"),
                StubNode(role: "AXButton", description: "進む"),
            ]),
            PanelTreeFixtures.button("キャンセル"),
            PanelTreeFixtures.button(confirmTitle),
        ]
    }

    /// サイドバー。項目は名前の要素（AXURL を持つ要素）を持たない。
    static func sidebar(id: String = "sidebar") -> StubNode {
        StubNode(id: id, role: "AXOutline", children: ["最近の項目", "アプリケーション", "デスクトップ"].map { title in
            StubNode(role: "AXRow", children: [
                StubNode(role: "AXCell", children: [StubNode(role: "AXStaticText", title: title), StubNode(role: "AXImage")]),
            ])
        })
    }

    // MARK: - 部品

    private static func nameField(_ item: FileListItem, id: String) -> StubNode {
        StubNode(
            id: id,
            role: "AXTextField",
            url: item.hasURL ? url(for: item) : nil,
            isEnabled: item.isEnabled,
            textOpacity: item.textOpacity
        )
    }
}
