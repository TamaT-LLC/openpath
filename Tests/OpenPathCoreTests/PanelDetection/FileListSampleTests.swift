import Testing

import OpenPathCore

/// 表示中の行だけでは推定できない一覧で、表示範囲の外の行も読む（Issue #73）。
@Suite("FileListRowSampler.sample（表示範囲の外の行）")
struct FileListSampleTests {
    private typealias Fixtures = FileListFixtures
    private typealias Read = StubPanelTree.Read

    private static let directoryRow = FileListRow(isDirectory: true)
    private static let dimmedFileRow = FileListRow(isDirectory: false, textOpacity: FileListFixtures.dimmedTextOpacity)
    private static let selectableFileRow = FileListRow(isDirectory: false, textOpacity: FileListFixtures.normalTextOpacity)

    /// 先頭にディレクトリが並び、末尾にファイルが並ぶ一覧（「フォルダを先頭に表示」の設定や、サブフォルダの多いフォルダ）。
    private static func directoriesFirst(directories: Int, files: [FileListItem]) -> [FileListItem] {
        (1...directories).map { FileListItem.directory(String(format: "dir-%02d", $0)) } + files
    }

    private static func sample(_ node: StubNode, in tree: StubPanelTree = StubPanelTree()) throws -> FileListSample {
        let fileList = tree.add(node)
        return try FileListRowSampler.sample(in: fileList, role: node.role ?? "", reader: tree)
    }

    // MARK: - 末尾の行

    @Test(
        "表示中の行がディレクトリだけなら、一覧の末尾から行を読む（カラム表示・リスト表示）",
        arguments: ["AXBrowser", "AXOutline"]
    )
    func readsTrailingRowsWhenVisibleRowsAreDirectories(role: String) throws {
        let items = Self.directoriesFirst(directories: 25, files: [.dimmedFile("a.txt"), .dimmedFile("b.txt")])
        let node = role == "AXBrowser"
            ? Fixtures.columnView(items: items, visibleItemCount: 15)
            : Fixtures.listView(items: items, visibleItemCount: 15)

        let sample = try Self.sample(node)

        // 表示中の 15 行の後の行（dir-16 以降）のうち、末尾の 10 行
        #expect(sample.trailingRows == Array(repeating: Self.directoryRow, count: 8) + [Self.dimmedFileRow, Self.dimmedFileRow])
        #expect(sample.leadingRows.filter { $0.isDirectory == false }.isEmpty)
    }

    @Test("末尾の行は、表示中の行と重ならない範囲だけ読む")
    func trailingRowsDoNotOverlapLeadingRows() throws {
        let tree = StubPanelTree()
        let items = Self.directoriesFirst(directories: 16, files: [.dimmedFile("a.txt")])
        let node = Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 15)

        let sample = try Self.sample(node, in: tree)

        #expect(sample.leadingRows.count == 15)
        #expect(sample.trailingRows == [Self.directoryRow, Self.dimmedFileRow])
        #expect(tree.reads.contains(Read(element: StubElement(Fixtures.listID(ofColumn: 0)), attribute: .items(.children))))
    }

    @Test("末尾の行でも、選べるファイルの行が見つかったら以降の行は読まない")
    func trailingRowsStopAtSelectableFile() throws {
        let tree = StubPanelTree()
        let items = Self.directoriesFirst(directories: 20, files: [.file("a.txt"), .file("b.txt")])
        let node = Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 15)

        let sample = try Self.sample(node, in: tree)

        #expect(sample.trailingRows.last == Self.selectableFileRow)
        let listID = "\(Fixtures.fileListID)/column/0"
        #expect(tree.reads.filter { $0.element == StubElement(Fixtures.nameID("b.txt", in: listID)) }.isEmpty)
    }

    @Test(
        "表示中の行にディレクトリ以外の行があるか、ディレクトリの行がなければ、末尾の行を読まない（要素数も読まない）",
        arguments: [
            ("ファイルの行がある", [FileListItem.directory("alpha"), .dimmedFile("a.txt")] + (1...20).map { FileListItem.directory("d\($0)") }),
            ("選べるファイルの行がある", [FileListItem.file("a.txt")] + (1...20).map { FileListItem.directory("d\($0)") }),
            ("空のフォルダ", [FileListItem]()),
        ]
    )
    func skipsTrailingRows(label: String, items: [FileListItem]) throws {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 15)

        let sample = try Self.sample(node, in: tree)

        #expect(sample.trailingRows.isEmpty, "\(label)")
        #expect(tree.readCount(of: .itemCount(.children)) == 0, "\(label)")
    }

    @Test("すべて表示中のディレクトリだけの一覧では、要素数を確かめるだけで行は読み直さない")
    func allVisibleDirectoriesReadOnlyCount() throws {
        let tree = StubPanelTree()
        let node = Fixtures.listView(items: (1...10).map { FileListItem.directory("d\($0)") })

        let sample = try Self.sample(node, in: tree)

        #expect(sample.trailingRows.isEmpty)
        #expect(tree.readCount(of: .itemCount(.rows)) == 1)
        #expect(tree.readCount(of: .items(.rows)) == 0)
    }

    @Test("アイコン表示では末尾の行を読まない（表示範囲の外の項目は実体がなく、読むと無効な要素になるため）")
    func iconViewDoesNotReadTrailingRows() throws {
        let tree = StubPanelTree()
        let items = Self.directoriesFirst(directories: 25, files: [.dimmedFile("a.txt")])
        let node = Fixtures.iconView(items: items, visibleItemCount: 15)

        let sample = try Self.sample(node, in: tree)

        #expect(sample.leadingRows == Array(repeating: Self.directoryRow, count: 15))
        #expect(sample.trailingRows.isEmpty)
        #expect(tree.readCount(of: .itemCount(.children)) == 0)
        #expect(tree.readCount(of: .items(.children)) == 0)
    }

    @Test("末尾の行を読む AX の呼び出し回数（カラム表示・リスト表示）", arguments: [
        // 要素数 1 + 範囲の読み取り 1、ディレクトリは名前の要素と URL の 2、ファイルは文字色を足して 3
        ("カラム表示", "AXBrowser", 2 + 8 * 2 + 2 * 3),
        // 要素数 1 + 範囲の読み取り 1、ディレクトリはセル・名前の要素・URL の 3、ファイルは文字色を足して 4
        ("リスト表示", "AXOutline", 2 + 8 * 3 + 2 * 4),
    ])
    func trailingAXCallCount(label: String, role: String, expected: Int) throws {
        let items = Self.directoriesFirst(directories: 25, files: [.dimmedFile("a.txt"), .dimmedFile("b.txt")])
        let node = role == "AXBrowser"
            ? Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 15)
            : Fixtures.listView(items: items, visibleItemCount: 15)
        let tree = StubPanelTree()
        let fileList = tree.add(node)
        let leading = try FileListRowSampler.sampleRows(in: fileList, role: role, reader: tree)
        let leadingReads = tree.reads.count
        tree.resetReads()

        let sample = try FileListRowSampler.sample(in: fileList, role: role, reader: tree)

        #expect(sample.leadingRows == leading, "\(label)")
        #expect(tree.reads.count - leadingReads == expected, "\(label)")
    }

    @Test("末尾の行まで読む場合の、推定 1 回の AX の呼び出し回数（先頭 20 行がディレクトリ・末尾 10 行が選べないファイル）", arguments: [
        // 先頭: 列 1 + 最後の列の子 1 + 子のロール 1 + 表示中の項目 1 + ディレクトリ 20 行 × 2。末尾: 2 + ファイル 10 行 × 3
        ("カラム表示", "AXBrowser", 4 + 20 * 2 + 2 + 10 * 3),
        // 先頭: 表示中の行 1 + 見出しの行 2 + ディレクトリ 19 行 × 3。末尾: 2 + ファイル 10 行 × 4
        ("リスト表示", "AXOutline", 1 + 2 + 19 * 3 + 2 + 10 * 4),
    ])
    func worstCaseAXCallCount(label: String, role: String, expected: Int) throws {
        let items = Self.directoriesFirst(directories: 25, files: (1...10).map { FileListItem.dimmedFile("f\($0).txt") })
        let node = role == "AXBrowser"
            ? Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 20)
            : Fixtures.listView(items: items, visibleItemCount: 20)
        let tree = StubPanelTree()

        let sample = try Self.sample(node, in: tree)

        #expect(sample.trailingRows == Array(repeating: Self.dimmedFileRow, count: 10), "\(label)")
        #expect(tree.reads.count == expected, "\(label)")
    }

    // MARK: - 表示範囲の外にある今のフォルダの列

    @Test("カラム表示で今のフォルダの列が表示範囲の外（表示中の項目がない）なら、列の先頭の項目を読む")
    func columnViewOutOfViewReadsLeadingChildren() throws {
        let tree = StubPanelTree()
        let items: [FileListItem] = [.directory("alpha"), .directory("beta"), .dimmedFile("c.txt"), .dimmedFile("d.txt")]
        let node = Fixtures.columnView(items: items, visibleItemCount: 0)

        let sample = try Self.sample(node, in: tree)

        #expect(sample.leadingRows == [Self.directoryRow, Self.directoryRow, Self.dimmedFileRow, Self.dimmedFileRow])
        #expect(sample.trailingRows.isEmpty)
        #expect(try FileListRowSampler.sampleRows(in: StubElement(Fixtures.fileListID), role: "AXBrowser", reader: tree) == sample.leadingRows)
    }

    @Test("カラム表示で今のフォルダの列が空なら、行はない")
    func columnViewEmptyFolder() throws {
        let sample = try Self.sample(Fixtures.columnView(items: [], visibleItemCount: 0))

        #expect(sample.leadingRows.isEmpty)
        #expect(sample.trailingRows.isEmpty)
    }

    @Test(
        "末尾の行の読み取りに失敗したら、末尾の行は読まなかったことにし、先頭の行は返す",
        arguments: [PanelTreeReadError.elementGone, .unavailable]
    )
    func trailingReadFailureKeepsLeadingRows(error: PanelTreeReadError) throws {
        let tree = StubPanelTree()
        let items = Self.directoriesFirst(directories: 20, files: [.dimmedFile("a.txt")])
        let node = Fixtures.columnView(ancestors: [], items: items, visibleItemCount: 15)
        tree.failures[StubElement(Fixtures.nameID("a.txt", in: "\(Fixtures.fileListID)/column/0"))] = error

        let sample = try Self.sample(node, in: tree)

        #expect(sample.leadingRows == Array(repeating: Self.directoryRow, count: 15))
        #expect(sample.trailingRows.isEmpty)
    }

    @Test("先頭の行の読み取りの失敗はそのまま投げる", arguments: [PanelTreeReadError.elementGone, .unavailable])
    func propagatesLeadingReadFailure(error: PanelTreeReadError) {
        let tree = StubPanelTree()
        let node = Fixtures.columnView(ancestors: [], items: [.directory("alpha"), .dimmedFile("a.txt")])
        tree.failures[StubElement(Fixtures.nameID("a.txt", in: "\(Fixtures.fileListID)/column/0"))] = error

        #expect(throws: error) {
            try Self.sample(node, in: tree)
        }
    }
}
