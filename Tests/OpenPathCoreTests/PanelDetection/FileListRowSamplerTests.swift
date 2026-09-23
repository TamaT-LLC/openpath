import Testing

import OpenPathCore

@Suite("FileListRowSampler（ファイル一覧の行の読み取り）")
struct FileListRowSamplerTests {
    private typealias Fixtures = FileListFixtures
    private typealias Read = StubPanelTree.Read

    private static let directoryRow = FileListRow(isDirectory: true)
    private static let dimmedFileRow = FileListRow(isDirectory: false, textOpacity: FileListFixtures.dimmedTextOpacity)
    private static let selectableFileRow = FileListRow(isDirectory: false, textOpacity: FileListFixtures.normalTextOpacity)

    private static func sample(
        _ node: StubNode,
        in tree: StubPanelTree = StubPanelTree(),
        limit: Int = PanelSelectionModeEstimator.sampledRowCount
    ) throws -> [FileListRow] {
        let fileList = tree.add(node)
        return try FileListRowSampler.sampleRows(in: fileList, role: node.role ?? "", reader: tree, limit: limit)
    }

    /// 名前の要素の読み取り（名前の要素の id を含む読み取り）。
    private static func nameReads(in tree: StubPanelTree, name: String, listID: String) -> [Read] {
        tree.reads.filter { $0.element == StubElement(Fixtures.nameID(name, in: listID)) }
    }

    // MARK: - カラム表示

    @Test("カラム表示では、最後の列（今のフォルダ）の項目を読み、親フォルダの列は読まない")
    func columnViewReadsLastColumn() throws {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(
            ancestors: [[.directory("Users"), .file("Users.txt")]],
            items: [.directory("alpha"), .directory("beta"), .dimmedFile("delta.md"), .dimmedFile("gamma.txt")]
        )

        let rows = try Self.sample(node, in: tree)

        #expect(rows == [Self.directoryRow, Self.directoryRow, Self.dimmedFileRow, Self.dimmedFileRow])
        #expect(Self.nameReads(in: tree, name: "Users", listID: "\(Fixtures.fileListID)/column/0").isEmpty)
    }

    @Test("右にプレビューの列（AXList を持たない）があれば、その左の列を今のフォルダとして読む")
    func columnViewSkipsPreviewColumn() throws {
        let node = Fixtures.columnView(items: [.directory("alpha"), .file("readme.md")], hasPreviewColumn: true)

        let rows = try Self.sample(node)

        #expect(rows == [Self.directoryRow, Self.selectableFileRow])
    }

    @Test("列がなければ行はない")
    func columnViewWithoutColumns() throws {
        let node = StubNode(id: Fixtures.fileListID, role: "AXBrowser", children: [StubNode(role: "AXScrollArea")])

        #expect(try Self.sample(node).isEmpty)
    }

    // MARK: - リスト表示

    @Test(
        "リスト表示では表示中の行を読み、名前の要素のない見出しの行は種類の分からない行にする",
        arguments: ["AXOutline", "AXTable"]
    )
    func listViewReadsVisibleRows(role: String) throws {
        let node = Fixtures.listView(role: role, items: [.dimmedFile("delta.md"), .directory("beta")])

        let rows = try Self.sample(node)

        #expect(rows == [FileListRow(isDirectory: nil), Self.dimmedFileRow, Self.directoryRow])
    }

    // MARK: - 読む行と AX の読み取り

    @Test("先頭の limit 行だけ読み、それより後の行の名前は読まない")
    func readsOnlyLeadingRows() throws {
        let tree = StubPanelTree()
        let items = (1...30).map { FileListItem.dimmedFile("file-\($0).txt") }
        let node = Fixtures.columnView(ancestors: [], items: items)
        let listID = "\(Fixtures.fileListID)/column/0"

        let rows = try Self.sample(node, in: tree)

        #expect(rows.count == PanelSelectionModeEstimator.sampledRowCount)
        #expect(!Self.nameReads(in: tree, name: "file-20.txt", listID: listID).isEmpty)
        #expect(Self.nameReads(in: tree, name: "file-21.txt", listID: listID).isEmpty)
    }

    @Test("選べるファイルの行が見つかったら、推定が確定するため以降の行は読まない")
    func stopsAtSelectableFile() throws {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: [.dimmedFile("a.txt"), .file("b.txt"), .dimmedFile("c.txt")])

        let rows = try Self.sample(node, in: tree)

        #expect(rows == [Self.dimmedFileRow, Self.selectableFileRow])
        #expect(Self.nameReads(in: tree, name: "c.txt", listID: "\(Fixtures.fileListID)/column/0").isEmpty)
    }

    @Test("ディレクトリの行は URL だけ読み、文字色と AXEnabled は読まない")
    func directoryRowsReadOnlyURL() throws {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: [.directory("alpha")])

        _ = try Self.sample(node, in: tree)

        let reads = Self.nameReads(in: tree, name: "alpha", listID: "\(Fixtures.fileListID)/column/0")
        #expect(reads.map(\.attribute) == [.url])
    }

    @Test("ファイルの行は文字色を読めれば AXEnabled を読まない")
    func fileRowsReadTextOpacity() throws {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: [.dimmedFile("a.txt")])

        _ = try Self.sample(node, in: tree)

        let reads = Self.nameReads(in: tree, name: "a.txt", listID: "\(Fixtures.fileListID)/column/0")
        #expect(reads.map(\.attribute) == [.url, .textOpacity])
    }

    @Test("文字色を読めない行（文字列を持たない要素）は AXEnabled を読む", arguments: [true, false])
    func fallsBackToEnabled(isEnabled: Bool) throws {
        var item = FileListItem.file("image.png")
        item.textOpacity = nil
        item.isEnabled = isEnabled
        let node = Fixtures.columnView(ancestors: [], items: [item])

        let rows = try Self.sample(node)

        #expect(rows == [FileListRow(isDirectory: false, isEnabled: isEnabled)])
    }

    @Test("URL を読めない名前の要素は、種類の分からない行としてそれ以上読まない")
    func rowWithoutURL() throws {
        let tree = StubPanelTree()
        var item = FileListItem.dimmedFile("a.txt")
        item.hasURL = false
        let node = Fixtures.columnView(ancestors: [], items: [item])

        let rows = try Self.sample(node, in: tree)

        #expect(rows == [FileListRow(isDirectory: nil)])
        let reads = Self.nameReads(in: tree, name: "a.txt", listID: "\(Fixtures.fileListID)/column/0")
        #expect(reads.map(\.attribute) == [.url])
    }

    @Test(
        "20 行を読む AX の呼び出し回数（ディレクトリ 10 行・選べないファイル 10 行）",
        arguments: [
            // 列 1 + 最後の列の子 1 + 子のロール 1 + 表示中の項目 1、ディレクトリは名前の要素と URL の 2、ファイルは文字色を足して 3
            ("カラム表示", "AXBrowser", 4 + 10 * 2 + 10 * 3),
            // 表示中の行 1 + 見出しの行（セル 1・名前の要素 1）、ディレクトリはセル・名前の要素・URL の 3、ファイルは文字色を足して 4。
            // 見出しの行も 20 行に数えるため、項目は 19 行（ディレクトリ 10・ファイル 9）
            ("リスト表示", "AXOutline", 1 + 2 + 10 * 3 + 9 * 4),
        ]
    )
    func axCallCount(label: String, role: String, expected: Int) throws {
        let tree = StubPanelTree()
        let items = (1...10).flatMap { [FileListItem.directory("dir-\($0)"), .dimmedFile("file-\($0).txt")] }
        let node = role == "AXBrowser"
            ? Fixtures.columnView(ancestors: [], items: items)
            : Fixtures.listView(items: items)

        _ = try Self.sample(node, in: tree)

        #expect(tree.reads.count == expected, "\(label)")
    }

    // MARK: - 対象外と失敗

    @Test("ファイル一覧でないロールでは何も読まない")
    func unsupportedRole() throws {
        let tree = StubPanelTree()
        let list = tree.add(StubNode(id: "list", role: "AXList", children: [StubNode(role: "AXGroup")]))

        let rows = try FileListRowSampler.sampleRows(in: list, role: "AXList", reader: tree)

        #expect(rows.isEmpty)
        #expect(tree.reads.isEmpty)
    }

    @Test("読み取りの失敗はそのまま投げる", arguments: [PanelTreeReadError.elementGone, .unavailable])
    func propagatesReadFailure(error: PanelTreeReadError) {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: [.dimmedFile("a.txt")])
        tree.failures[StubElement(Fixtures.nameID("a.txt", in: "\(Fixtures.fileListID)/column/0"))] = error

        #expect(throws: error) {
            try Self.sample(node, in: tree)
        }
    }
}
