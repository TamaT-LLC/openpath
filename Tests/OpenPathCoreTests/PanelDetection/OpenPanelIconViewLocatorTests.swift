import Testing

import OpenPathCore

@Suite("OpenPanelLocator: アイコン表示のパネルの検知と選択モードの推定")
struct OpenPanelIconViewLocatorTests {
    private typealias Fixtures = FileListFixtures
    private typealias PanelFixtures = PanelTreeFixtures

    /// Claude Desktop の「フォルダを追加」のような、フォルダのみ選べるパネルの一覧。
    private static let folderOnlyItems: [FileListItem] = [
        .directory("alpha"), .directory("beta"), .dimmedFile("delta.md"), .dimmedFile("gamma.txt"),
    ]
    /// Safari の `input[type=file]` のような、ファイルも選べるパネルの一覧。
    private static let filesItems: [FileListItem] = [.directory("alpha"), .file("delta.md"), .file("gamma.txt")]
    /// 再判定の時刻（250ms から倍々に 4 回）と、それより後の時刻。
    private static let recheckTimes = [250, 750, 1_750, 3_750, 10_000]

    private static func dialog(_ iconView: StubNode, sidebar: StubNode? = Fixtures.sidebar()) -> StubNode {
        PanelFixtures.dialog(id: "open", Fixtures.openPanelBody(fileList: iconView, sidebar: sidebar))
    }

    private static func genericList(subrole: String?) -> StubNode {
        StubNode(role: "AXScrollArea", children: [
            StubNode(role: "AXList", subrole: subrole, children: ["iCloud", "Google"].map { name in
                PanelFixtures.group([StubNode(role: "AXStaticText", title: name)])
            }),
        ])
    }

    // MARK: - 検知と推定

    @Test("フォルダのみのパネル（アイコン表示）を検知し、isDirectoriesOnly を true にする（サイドバーの有無を問わない）", arguments: [true, false])
    func folderOnlyIconView(hasSidebar: Bool) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(
            Fixtures.iconView(items: Self.folderOnlyItems),
            sidebar: hasSidebar ? Fixtures.sidebar() : nil
        ))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
        #expect(panel.context.isDirectoriesOnly)
    }

    @Test(
        "ファイルも選べるパネル（アイコン表示）は filesSelectable にする（種類で絞り込むパネルを含む）",
        arguments: [
            ("ファイルも選べる", Self.filesItems),
            ("種類で絞り込む", [FileListItem.directory("alpha"), .dimmedFile("gamma.txt"), .file("delta.md")]),
        ]
    )
    func filesSelectableIconView(label: String, items: [FileListItem]) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.iconView(items: items)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .filesSelectable, "\(label)")
        #expect(!panel.context.isDirectoriesOnly, "\(label)")
    }

    @Test("サンドボックスアプリのリモートシート（アイコン表示・「追加」）でも検知して推定する")
    func folderOnlyRemoteSheet() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelFixtures.documentWindow(id: "document", sheets: [
            PanelFixtures.remoteSheet(id: "sheet", Fixtures.openPanelBody(
                fileList: Fixtures.iconView(items: Self.folderOnlyItems),
                sidebar: nil,
                confirmTitle: "追加"
            )),
        ]))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.element == StubElement("sheet"))
        #expect(panel.context.isDirectoriesOnly)
    }

    @Test("サイドバーを読むと推定を誤る並びでも、アイコン表示の一覧から推定する")
    func usesIconViewInsteadOfSidebar() throws {
        let harness = OpenPanelLocatorHarness()
        // サイドバーを誤って読むと、選べるファイルの行があるため「ファイルも選べる」になる
        let misleadingSidebar = Fixtures.listView(id: "sidebar", items: [.file("sidebar-item.txt")])
        let window = harness.add(Self.dialog(Fixtures.iconView(items: Self.folderOnlyItems), sidebar: misleadingSidebar))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .directoriesOnly)
    }

    @Test(
        "推定できないアイコン表示（ディレクトリのみ・空）は include_files に従うよう isDirectoriesOnly を false にする",
        arguments: [
            ("ディレクトリのみ", [FileListItem.directory("alpha"), .directory("beta")]),
            ("空のフォルダ", [FileListItem]()),
        ]
    )
    func undeterminedIconView(label: String, items: [FileListItem]) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.iconView(items: items)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.selectionMode == .undetermined, "\(label)")
        #expect(!panel.context.isDirectoriesOnly, "\(label)")
    }

    @Test("一覧の読み込み前（セクションがない）で推定できなかったら、250ms 後の走査で推定し直す")
    func retriesWhenIconViewIsNotLoaded() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.iconView(sections: [])))
        #expect(try #require(harness.panel(in: window)).selectionMode == .undetermined)

        harness.tree.replace(Fixtures.iconView(items: Self.folderOnlyItems))

        #expect(harness.panel(in: window, at: .milliseconds(250))?.selectionMode == .directoriesOnly)
    }

    // MARK: - 誤検知しない

    @Test("アイコン表示の保存パネル（シート）は、開くパネルとして見つけない", arguments: PanelUILanguage.allCases)
    func iconViewSavePanelIsNotFound(language: PanelUILanguage) {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelFixtures.documentWindow(id: "document", sheets: [
            PanelFixtures.sheet(id: "save", PanelFixtures.savePanelBody(
                language,
                fileList: Fixtures.iconView(items: Self.folderOnlyItems)
            )),
        ]))

        #expect(harness.locate(window) == .notFound)
    }

    @Test(
        "一般的な AXList と確定ボタンを持つ設定のシートは、再判定を経ても開くパネルとして見つけない",
        arguments: [nil, "AXSectionList", "AXContentList"] as [String?]
    )
    func settingsSheetWithGenericListIsNotFound(subrole: String?) {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelFixtures.documentWindow(id: "document", sheets: [
            PanelFixtures.sheet(id: "settings", [
                Self.genericList(subrole: subrole),
                PanelFixtures.button("キャンセル"),
                PanelFixtures.button("追加"),
            ]),
        ]))

        #expect(harness.locate(window) == .notFound)
        for elapsed in Self.recheckTimes {
            #expect(harness.locate(window, at: .milliseconds(elapsed)) == .notFound, "\(elapsed)ms")
        }
    }

    @Test("一般的な AXList を持つ「開く」ボタンのアラートは、開くパネルとして見つけない", arguments: PanelUILanguage.allCases)
    func alertWithGenericListIsNotFound(language: PanelUILanguage) {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelFixtures.dialog(
            id: "alert",
            PanelFixtures.alertBody(language) + [Self.genericList(subrole: nil)]
        ))

        #expect(harness.locate(window) == .notFound)
        for elapsed in Self.recheckTimes {
            #expect(harness.locate(window, at: .milliseconds(elapsed)) == .notFound, "\(elapsed)ms")
        }
    }
}
