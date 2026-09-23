import Testing

import OpenPathCore

@Suite("OpenPanelLocator: 選択モードの推定（DSN-001 §2.3）")
struct OpenPanelSelectionModeTests {
    private typealias Fixtures = FileListFixtures
    private typealias PanelFixtures = PanelTreeFixtures

    /// Claude Desktop の「フォルダを追加」のような、フォルダのみ選べるパネルの一覧（カラム表示）。
    private static let folderOnlyItems: [FileListItem] = [
        .directory("alpha"), .directory("beta"), .dimmedFile("delta.md"), .dimmedFile("gamma.txt"),
    ]
    /// Safari の `input[type=file]` のような、ファイルも選べるパネルの一覧。
    private static let filesItems: [FileListItem] = [
        .directory("alpha"), .file("delta.md"), .file("gamma.txt"),
    ]

    private static func dialog(_ fileList: StubNode) -> StubNode {
        PanelFixtures.dialog(id: "open", Fixtures.openPanelBody(fileList: fileList))
    }

    /// サンドボックスアプリのパネル（ホストのウィンドウの子のリモートシート）。
    private static func documentWithRemoteSheet(_ fileList: StubNode, confirmTitle: String = "開く") -> StubNode {
        PanelFixtures.documentWindow(id: "document", sheets: [
            PanelFixtures.remoteSheet(id: "sheet", Fixtures.openPanelBody(fileList: fileList, confirmTitle: confirmTitle)),
        ])
    }

    // MARK: - 推定の結果

    @Test("フォルダのみのパネル（カラム表示）は isDirectoriesOnly を true にする")
    func folderOnlyColumnView() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: Self.folderOnlyItems)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
        #expect(panel.context.isDirectoriesOnly)
    }

    @Test("フォルダのみのパネル（リスト表示）は isDirectoriesOnly を true にする")
    func folderOnlyListView() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.listView(items: Self.folderOnlyItems)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
        #expect(panel.context.isDirectoriesOnly)
    }

    @Test("サンドボックスアプリのリモートシートでも推定する（「追加」ボタンのフォルダのみのパネル）")
    func folderOnlyRemoteSheet() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithRemoteSheet(
            Fixtures.columnView(items: Self.folderOnlyItems),
            confirmTitle: "追加"
        ))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.element == StubElement("sheet"))
        #expect(panel.context.isDirectoriesOnly)
    }

    @Test("ファイルも選べるパネル（アップロード）は isDirectoriesOnly を false にする")
    func filesSelectablePanel() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithRemoteSheet(
            Fixtures.columnView(items: Self.filesItems),
            confirmTitle: "アップロード"
        ))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .filesSelectable)
        #expect(!panel.context.isDirectoriesOnly)
    }

    @Test(
        "推定できない一覧（ディレクトリのみ・空）は include_files に従うよう isDirectoriesOnly を false にする",
        arguments: [
            ("ディレクトリのみ", [FileListItem.directory("alpha"), .directory("beta")]),
            ("空のフォルダ", [FileListItem]()),
        ]
    )
    func undeterminedPanel(label: String, items: [FileListItem]) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: items)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined, "\(label)")
        #expect(!panel.context.isDirectoriesOnly, "\(label)")
    }

    @Test("サイドバー（先に現れる AXOutline）ではなく、中身のファイル一覧から推定する")
    func usesContentListInsteadOfSidebar() throws {
        let harness = OpenPanelLocatorHarness()
        // サイドバーを誤って読むと、選べるファイルの行があるため「ファイルも選べる」になる
        let misleadingSidebar = Fixtures.listView(id: "sidebar", items: [.file("sidebar-item.txt")])
        let window = harness.add(PanelFixtures.dialog(id: "open", Fixtures.openPanelBody(
            fileList: Fixtures.columnView(items: Self.folderOnlyItems),
            sidebar: misleadingSidebar
        )))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
    }

    @Test("行を持たない既存のパネルの形（行に名前の要素がない）は推定できない")
    func legacyFixtureIsUndetermined() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelFixtures.dialog(id: "open", PanelFixtures.openPanelBody(.japanese)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined)
        #expect(!panel.context.isDirectoriesOnly)
    }

    // MARK: - 推定は最初の判定で 1 度だけ

    @Test("推定は開くパネルと判定したときの 1 度だけ。フォルダを移動して行が変わっても推定し直さず、行も読まない")
    func estimatesOnlyOnFirstClassification() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: Self.folderOnlyItems)))
        let first = try #require(harness.panel(in: window))
        #expect(first.isNewlyClassified)

        // ⌘⇧G で移動した先のフォルダ（ディレクトリしかない）に差し替える
        harness.tree.replace(Fixtures.columnView(items: [.directory("repos")]))
        harness.tree.resetReads()
        let second = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(second.context == first.context)
        #expect(second.selectionMode == .directoriesOnly)
        #expect(!second.isNewlyClassified)
        #expect(harness.tree.readCount(of: .url) == 0)
        #expect(harness.tree.readCount(of: .textOpacity) == 0)
    }

    @Test("一時的な失敗で直前のパネルを引き継ぐときも、選択モードを保つ")
    func lastKnownPanelKeepsSelectionMode() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithRemoteSheet(Fixtures.columnView(items: Self.folderOnlyItems)))
        _ = try #require(harness.panel(in: window))

        harness.tree.failures[window] = .unavailable
        let lastKnown = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(lastKnown.selectionMode == .directoriesOnly)
        #expect(lastKnown.context.isDirectoriesOnly)
    }

    // MARK: - 推定の失敗

    @Test(
        "行の読み取りに失敗してもパネルは見つけ、推定できなかったものとして扱う",
        arguments: [PanelTreeReadError.elementGone, .unavailable]
    )
    func estimationFailureDoesNotBlockDetection(error: PanelTreeReadError) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: Self.folderOnlyItems)))
        let columnID = "\(Fixtures.fileListID)/column/1"
        harness.tree.failures[StubElement(Fixtures.nameID("delta.md", in: columnID))] = error

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined)
        #expect(!panel.context.isDirectoriesOnly)
        #expect(panel.context.id.rawValue.hasPrefix("open-panel-"))
    }
}
