import Testing

import OpenPathCore

@Suite("OpenPanelClassifier: アイコン表示のファイル一覧（AXList / AXCollectionList）")
struct OpenPanelIconViewClassifierTests {
    private typealias Fixtures = PanelTreeFixtures
    private typealias ListFixtures = FileListFixtures

    private static let iconViewID = StubElement(FileListFixtures.fileListID)
    /// フォルダのみのパネルのアイコン表示。
    private static let iconView = FileListFixtures.iconView(items: [.directory("alpha"), .dimmedFile("delta.md")])
    /// サブロールが AXCollectionList でない AXList のサブロール（nil はサブロールなし）。
    private static let genericListSubroles: [String?] = [nil, "AXSectionList", "AXContentList", "AXDefinitionList"]

    private static func classification(
        _ node: StubNode,
        in tree: StubPanelTree = StubPanelTree()
    ) throws -> OpenPanelClassification<StubElement> {
        let candidate = tree.add(node)
        return try OpenPanelClassifier.classification(of: candidate, reader: tree)
    }

    /// 設定のシートなどにある一般的な一覧。項目はファイルではない。
    private static func genericList(subrole: String?) -> StubNode {
        StubNode(role: "AXScrollArea", children: [
            StubNode(role: "AXList", subrole: subrole, children: ["iCloud", "Google", "Dropbox"].map { name in
                Fixtures.group([StubNode(role: "AXStaticText", title: name), StubNode(role: "AXImage")])
            }),
        ])
    }

    // MARK: - 開くパネル

    @Test("アイコン表示の開くパネルを判定し、サイドバーではなくアイコン表示の一覧を中身の一覧とする", arguments: PanelUILanguage.allCases)
    func iconViewPanelIsDetected(language: PanelUILanguage) throws {
        let dialog = Fixtures.dialog(
            id: "open",
            ListFixtures.openPanelBody(fileList: Self.iconView, confirmTitle: language.labels.open)
        )

        let result = try Self.classification(dialog)

        #expect(result.verdict == .openPanel)
        #expect(result.fileList == FileListElement(node: Self.iconViewID, role: "AXList"))
    }

    @Test("サイドバーを隠したアイコン表示の開くパネル（ファイル一覧のロールの要素が AXList だけ）も判定する")
    func iconViewPanelWithoutSidebar() throws {
        let dialog = Fixtures.dialog(id: "open", ListFixtures.openPanelBody(fileList: Self.iconView, sidebar: nil))

        let result = try Self.classification(dialog)

        #expect(result.verdict == .openPanel)
        #expect(result.fileList == FileListElement(node: Self.iconViewID, role: "AXList"))
    }

    @Test("サンドボックスアプリのリモートシート（アイコン表示）も判定する", arguments: ["開く", "追加", "アップロード", "Choose"])
    func remoteIconViewSheetIsDetected(confirmTitle: String) throws {
        let sheet = Fixtures.remoteSheet(
            id: "remote",
            ListFixtures.openPanelBody(fileList: Self.iconView, sidebar: nil, confirmTitle: confirmTitle)
        )

        #expect(try Self.classification(sheet).verdict == .openPanel)
    }

    // MARK: - 誤検知しない

    @Test(
        "アイコン表示の保存パネルは、確定ボタンが「選択」等でも保存パネルと判定する",
        arguments: PanelUILanguage.allCases, [nil, "選択", "Open"] as [String?]
    )
    func iconViewSavePanelIsRejected(language: PanelUILanguage, confirmTitle: String?) throws {
        let dialog = Fixtures.dialog(
            id: "save",
            Fixtures.savePanelBody(language, confirmTitle: confirmTitle, fileList: Self.iconView)
        )

        #expect(try Self.classification(dialog).verdict == .savePanel)
    }

    @Test(
        "サブロールが AXCollectionList でない AXList（設定のシートの一覧など）はファイル一覧とみなさない",
        arguments: Self.genericListSubroles, ["追加", "Add", "選択", "Choose", "開く", "Open"]
    )
    func genericListIsNotFileList(subrole: String?, confirmTitle: String) throws {
        let sheet = Fixtures.sheet(id: "settings", [
            StubNode(role: "AXStaticText", title: "アカウント"),
            Self.genericList(subrole: subrole),
            Fixtures.button("キャンセル"),
            Fixtures.button(confirmTitle),
        ])

        let result = try Self.classification(sheet)

        #expect(result.verdict == .missingElements(hasConfirmButton: true, hasFileList: false))
        #expect(result.fileList == nil)
    }

    @Test("「開く」ボタンを持つアラートに一般的な AXList があっても、開くパネルではない", arguments: PanelUILanguage.allCases)
    func alertWithGenericListIsNotOpenPanel(language: PanelUILanguage) throws {
        let alert = Fixtures.dialog(id: "alert", Fixtures.alertBody(language) + [Self.genericList(subrole: nil)])

        #expect(try Self.classification(alert).verdict == .missingElements(hasConfirmButton: true, hasFileList: false))
    }

    @Test("アイコン表示の一覧があっても、確定ボタンがなければ開くパネルではない")
    func iconViewWithoutConfirmButtonIsNotOpenPanel() throws {
        let dialog = Fixtures.dialog(id: "panel", ListFixtures.openPanelBody(fileList: Self.iconView, confirmTitle: "Export"))

        #expect(try Self.classification(dialog).verdict == .missingElements(hasConfirmButton: false, hasFileList: true))
    }

    @Test("ファイル一覧の条件は、リスト表示・カラム表示のロールか、サブロールが AXCollectionList の AXList")
    func fileListCriteria() {
        for role in ["AXBrowser", "AXOutline", "AXTable"] {
            #expect(OpenPanelCriteria.isFileList(role: role, subrole: nil))
        }
        #expect(OpenPanelCriteria.isFileList(role: "AXList", subrole: "AXCollectionList"))
        for subrole in Self.genericListSubroles {
            #expect(!OpenPanelCriteria.isFileList(role: "AXList", subrole: subrole))
        }
        #expect(!OpenPanelCriteria.isFileList(role: "AXGroup", subrole: "AXCollectionList"))
    }

    // MARK: - AX の読み取り

    @Test("サブロールは AXList の要素だけ読み、アイコン表示の一覧の中へは降りない")
    func readsSubroleOnlyForLists() throws {
        let tree = StubPanelTree()

        _ = try Self.classification(Fixtures.dialog(id: "open", ListFixtures.openPanelBody(fileList: Self.iconView)), in: tree)

        #expect(tree.reads.filter { $0.attribute == .subrole }.map(\.element) == [Self.iconViewID])
        #expect(!tree.reads.contains(StubPanelTree.Read(element: Self.iconViewID, attribute: .children)))
    }
}
