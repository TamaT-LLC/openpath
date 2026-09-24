import Testing

import OpenPathCore

/// フォルダのみのパネル（`choose folder` など）で、表示中の行だけでは推定できない場合（Issue #73）。
@Suite("OpenPanelLocator: 表示範囲の外の行も使った選択モードの推定")
struct OpenPanelSelectionModeLookAheadTests {
    private typealias Fixtures = FileListFixtures

    /// 表示中の 15 行がディレクトリで、末尾に選べないファイルが並ぶ一覧（フォルダのみのパネル）。
    private static let folderOnlyDirectoriesFirst: [FileListItem] =
        (1...25).map { FileListItem.directory(String(format: "dir-%02d", $0)) } + [.dimmedFile("a.txt"), .dimmedFile("b.txt")]
    /// 同じ並びで、ファイルが選べる一覧（ファイルも選べるパネル）。
    private static let filesDirectoriesFirst: [FileListItem] =
        (1...25).map { FileListItem.directory(String(format: "dir-%02d", $0)) } + [.file("a.txt"), .file("b.txt")]

    private static func dialog(_ fileList: StubNode) -> StubNode {
        PanelTreeFixtures.dialog(id: "open", Fixtures.openPanelBody(fileList: fileList, confirmTitle: "選択"))
    }

    private static func fileList(role: String, items: [FileListItem], visibleItemCount: Int?) -> StubNode {
        switch role {
        case "AXBrowser":
            Fixtures.columnView(items: items, visibleItemCount: visibleItemCount)
        case "AXList":
            Fixtures.iconView(items: items, visibleItemCount: visibleItemCount)
        default:
            Fixtures.listView(items: items, visibleItemCount: visibleItemCount)
        }
    }

    @Test(
        "表示中の行がディレクトリだけのフォルダのみのパネルは、末尾の行から directoriesOnly と推定する",
        arguments: ["AXBrowser", "AXOutline"]
    )
    func folderOnlyWithDirectoriesFirst(role: String) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Self.fileList(role: role, items: Self.folderOnlyDirectoriesFirst, visibleItemCount: 15)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
        #expect(panel.context.isDirectoriesOnly)
        #expect(!panel.context.isSelectionModeProvisional)
    }

    @Test(
        "同じ並びでファイルも選べるパネルは filesSelectable と推定する",
        arguments: ["AXBrowser", "AXOutline"]
    )
    func filesSelectableWithDirectoriesFirst(role: String) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Self.fileList(role: role, items: Self.filesDirectoriesFirst, visibleItemCount: 15)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .filesSelectable)
        #expect(!panel.context.isDirectoriesOnly)
    }

    @Test("アイコン表示は末尾の行を読まないため、表示中の項目がディレクトリだけなら推定できない（読めた行はあるので推定し直さない）")
    func iconViewWithDirectoriesFirstIsUndetermined() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Self.fileList(role: "AXList", items: Self.folderOnlyDirectoriesFirst, visibleItemCount: 15)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined)
        #expect(!panel.context.isSelectionModeProvisional)
        #expect(panel.selectionEstimate.sampledDirectoryCount == 15)
    }

    @Test("カラム表示で今のフォルダの列が表示範囲の外でも、列の項目から推定し、推定し直しを待たない")
    func columnOutOfView() throws {
        let harness = OpenPanelLocatorHarness()
        let items: [FileListItem] = [.directory("alpha"), .dimmedFile("c.txt")]
        let window = harness.add(Self.dialog(Fixtures.columnView(items: items, visibleItemCount: 0)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
        #expect(!panel.context.isSelectionModeProvisional)
    }

    @Test(
        "ディレクトリしかない・空のフォルダは推定できず、include_files に従う（isDirectoriesOnly は false）",
        arguments: [
            ("ディレクトリのみ（表示範囲の外にも）", (1...25).map { FileListItem.directory("d\($0)") }, 25),
            ("空のフォルダ", [FileListItem](), 0),
        ]
    )
    func undeterminedFolders(label: String, items: [FileListItem], directories: Int) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: items, visibleItemCount: 15)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined, "\(label)")
        #expect(!panel.context.isDirectoriesOnly, "\(label)")
        #expect(panel.selectionEstimate.sampledFileCount == 0, "\(label)")
        #expect(panel.selectionEstimate.sampledDirectoryCount == min(directories, 15 + 10), "\(label)")
    }

    @Test("推定に使った行の内訳を、見つけたパネルと一緒に返す")
    func reportsSampledRows() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: Self.folderOnlyDirectoriesFirst, visibleItemCount: 15)))

        let panel = try #require(harness.panel(in: window))

        // 表示中の 15 行と末尾の 10 行（ディレクトリ 8・ファイル 2）
        #expect(panel.selectionEstimate == PanelSelectionEstimate(
            mode: .directoriesOnly,
            sampledRowCount: 25,
            sampledDirectoryCount: 23,
            sampledFileCount: 2
        ))
    }

    @Test("行の読み取りに失敗したパネルは、内訳のない「推定できない」を返す")
    func reportsNotSampledOnFailure() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: [.dimmedFile("a.txt")])))
        harness.tree.failures[StubElement(Fixtures.nameID("a.txt", in: "\(Fixtures.fileListID)/column/1"))] = .unavailable

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionEstimate == .notSampled)
    }
}
