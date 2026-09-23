import Testing

import OpenPathCore

@Suite("OpenPanelClassifier: パネルの候補の判定（条件 2〜4）")
struct OpenPanelClassifierTests {
    private typealias Fixtures = PanelTreeFixtures

    private static func classify(_ node: StubNode, in tree: StubPanelTree = StubPanelTree()) throws -> OpenPanelVerdict {
        let candidate = tree.add(node)
        return try OpenPanelClassifier.classify(candidate, reader: tree)
    }

    // MARK: - 開くパネル

    @Test("NSOpenPanel を開くパネルと判定する", arguments: PanelUILanguage.allCases)
    func openPanelIsDetected(language: PanelUILanguage) throws {
        let dialog = Fixtures.dialog(id: "open", Fixtures.openPanelBody(language))

        #expect(try Self.classify(dialog) == .openPanel)
    }

    @Test(
        "確定ボタンのタイトルはいずれも確定ボタンとみなす",
        arguments: ["開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload"]
    )
    func everyConfirmTitleIsAccepted(title: String) throws {
        let dialog = Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese, confirmTitle: title))

        #expect(try Self.classify(dialog) == .openPanel)
    }

    @Test("ファイル一覧は AXBrowser / AXOutline / AXTable のいずれでもよい", arguments: ["AXBrowser", "AXOutline", "AXTable"])
    func everyFileListRoleIsAccepted(role: String) throws {
        let dialog = Fixtures.dialog(id: "open", [
            Fixtures.group([Fixtures.fileList(role: role)]),
            Fixtures.button("開く"),
        ])

        #expect(try Self.classify(dialog) == .openPanel)
    }

    @Test("サンドボックスアプリのパネル（リモートビューの下に中身がある）も判定する", arguments: PanelUILanguage.allCases)
    func remotePanelIsDetected(language: PanelUILanguage) throws {
        let sheet = Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(language))

        #expect(try Self.classify(sheet) == .openPanel)
    }

    // MARK: - 確定ボタン・ファイル一覧が欠けている

    @Test("確定ボタンがなければ開くパネルではない")
    func missingConfirmButton() throws {
        let dialog = Fixtures.dialog(id: "panel", Fixtures.openPanelBody(.english, confirmTitle: "Export"))

        #expect(try Self.classify(dialog) == .missingElements(hasConfirmButton: false, hasFileList: true))
    }

    @Test("ファイル一覧がなければ開くパネルではない（「開く」ボタンを持つアラート）", arguments: PanelUILanguage.allCases)
    func alertWithOpenButtonIsNotOpenPanel(language: PanelUILanguage) throws {
        let alert = Fixtures.dialog(id: "alert", Fixtures.alertBody(language))

        #expect(try Self.classify(alert) == .missingElements(hasConfirmButton: true, hasFileList: false))
    }

    @Test("確定ボタンのタイトルは完全一致で比べる（前後の空白は無視する）")
    func confirmTitleMatchesExactly() throws {
        #expect(OpenPanelCriteria.isConfirmButtonTitle(" 開く "))
        #expect(OpenPanelCriteria.isConfirmButtonTitle("Open"))
        #expect(!OpenPanelCriteria.isConfirmButtonTitle("開くアプリ"))
        #expect(!OpenPanelCriteria.isConfirmButtonTitle("Open Recent"))
        #expect(!OpenPanelCriteria.isConfirmButtonTitle("open"))
    }

    @Test("中身がまだないシート（描画途中）は要素が欠けているとする")
    func emptySheetIsMissingElements() throws {
        let sheet = Fixtures.sheet(id: "loading", [])

        #expect(try Self.classify(sheet) == .missingElements(hasConfirmButton: false, hasFileList: false))
    }

    // MARK: - 保存パネル（条件 4）

    @Test("NSSavePanel は保存パネルと判定する", arguments: PanelUILanguage.allCases)
    func savePanelIsRejected(language: PanelUILanguage) throws {
        let dialog = Fixtures.dialog(id: "save", Fixtures.savePanelBody(language))

        #expect(try Self.classify(dialog) == .savePanel)
    }

    @Test("確定ボタンが「選択」等に変えられた保存パネルも、ファイル名欄で保存パネルと判定する", arguments: PanelUILanguage.allCases)
    func savePanelWithCustomPromptIsRejected(language: PanelUILanguage) throws {
        let dialog = Fixtures.dialog(id: "save", Fixtures.savePanelBody(language, confirmTitle: "選択"))

        #expect(try Self.classify(dialog) == .savePanel)
    }

    @Test(
        "入力欄の説明かタイトルに「Save」「保存」「名前」を含めば保存パネルのファイル名欄とみなす",
        arguments: [
            ("Save As:", nil),
            ("別名で保存:", nil),
            ("名前:", nil),
            (nil, "名前"),
            (nil, "Save As:"),
        ] as [(String?, String?)]
    )
    func saveFieldLabels(description: String?, title: String?) throws {
        let dialog = Fixtures.dialog(id: "panel", Fixtures.openPanelBody(.japanese) + [
            Fixtures.textField(description: description, title: title),
        ])

        #expect(try Self.classify(dialog) == .savePanel)
    }

    @Test("検索欄は保存パネルのファイル名欄とみなさない")
    func searchFieldIsNotSaveField() throws {
        let dialog = Fixtures.dialog(id: "open", [
            Fixtures.textField(description: "検索", subrole: "AXSearchField"),
            Fixtures.textField(description: "Search", subrole: "AXSearchField"),
            Fixtures.fileList(role: "AXBrowser"),
            Fixtures.button("開く"),
        ])

        #expect(try Self.classify(dialog) == .openPanel)
    }

    @Test("子のシート（⌘⇧G の移動先シートや、ダイアログに付いたパネル）の中は候補の判定に含めない")
    func childSheetsAreNotPartOfCandidate() throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "settings", Fixtures.alertBody(.japanese) + [
            Fixtures.sheet(id: "sheet", Fixtures.savePanelBody(.japanese, confirmTitle: "開く")),
        ]))

        let verdict = try OpenPanelClassifier.classify(dialog, reader: tree)

        #expect(verdict == .missingElements(hasConfirmButton: true, hasFileList: false))
        #expect(!tree.reads.contains(StubPanelTree.Read(element: StubElement("sheet"), attribute: .children)))
    }

    @Test("ボタンのタイトルに「保存」を含んでも、入力欄でなければ保存パネルとはみなさない")
    func saveKeywordOnButtonIsIgnored() throws {
        let dialog = Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese) + [Fixtures.button("保存先を表示")])

        #expect(try Self.classify(dialog) == .openPanel)
    }

    // MARK: - AX の往復を抑える

    @Test("ファイル一覧の中へは降りない（行のファイル名を保存欄と誤認せず、往復も減らす）")
    func doesNotDescendIntoFileLists() throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "open", [
            Fixtures.fileList(role: "AXBrowser", id: "browser"),
            Fixtures.fileList(role: "AXOutline", id: "outline"),
            Fixtures.fileList(role: "AXTable", id: "table"),
            Fixtures.button("開く"),
        ]))

        #expect(try OpenPanelClassifier.classify(dialog, reader: tree) == .openPanel)
        for list in ["browser", "outline", "table"].map(StubElement.init) {
            #expect(!tree.reads.contains(StubPanelTree.Read(element: list, attribute: .children)))
        }
    }

    @Test("ファイル一覧の中にある「開く」ボタンは確定ボタンとみなさない")
    func openButtonInsideFileListIsIgnored() throws {
        let dialog = Fixtures.dialog(id: "panel", [
            Fixtures.fileList(role: "AXBrowser"),
            Fixtures.button("キャンセル"),
        ])

        #expect(try Self.classify(dialog) == .missingElements(hasConfirmButton: false, hasFileList: true))
    }

    @Test("タイトルはボタンと入力欄、説明は入力欄だけ読む")
    func readsTitlesOnlyWhereNeeded() throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))

        _ = try OpenPanelClassifier.classify(dialog, reader: tree)

        #expect(tree.readCount(of: .title) > 0)
        for read in tree.reads where read.attribute == .title {
            #expect(["AXButton", "AXTextField"].contains(tree.storedRole(of: read.element)))
        }
        for read in tree.reads where read.attribute == .description {
            #expect(tree.storedRole(of: read.element) == "AXTextField")
        }
    }

    @Test("ロールは 1 要素につき 1 回だけ読み、サブロールは読まない")
    func readsEachRoleOnce() throws {
        let tree = StubPanelTree()
        let sheet = tree.add(Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(.english)))

        _ = try OpenPanelClassifier.classify(sheet, reader: tree)

        let roleReads = tree.reads.filter { $0.attribute == .role }.map(\.element)
        #expect(roleReads.count == Set(roleReads).count)
        #expect(tree.readCount(of: .subrole) == 0)
        #expect(tree.readCount(of: .frame) == 0)
    }

    @Test("保存パネルと分かった時点で以降の要素を読まない")
    func stopsReadingAfterSaveField() throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "save", [
            Fixtures.textField(description: "Save As:"),
            StubNode(id: "later", role: "AXGroup", children: [Fixtures.button("Open")]),
        ]))

        #expect(try OpenPanelClassifier.classify(dialog, reader: tree) == .savePanel)
        #expect(!tree.reads.contains(StubPanelTree.Read(element: StubElement("later"), attribute: .children)))
    }

    @Test("探索の上限（6 階層）より深い確定ボタンは見ない")
    func respectsDepthLimit() throws {
        var deepest = Fixtures.button("開く")
        for _ in 0..<BoundedBreadthFirstSearch.defaultMaxDepth {
            deepest = Fixtures.group([deepest])
        }
        let dialog = Fixtures.dialog(id: "deep", [Fixtures.fileList(role: "AXTable"), deepest])

        #expect(try Self.classify(dialog) == .missingElements(hasConfirmButton: false, hasFileList: true))
    }

    // MARK: - 読み取りの失敗

    @Test("読み取りに失敗したら、判定せずにエラーをそのまま投げる", arguments: [PanelTreeReadError.unavailable, .elementGone])
    func readFailureIsThrown(error: PanelTreeReadError) throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        tree.failures[dialog] = error

        #expect(throws: error) {
            try OpenPanelClassifier.classify(dialog, reader: tree)
        }
    }

    @Test("判定の途中で子孫が消えていたら、候補は残っているので一時的に読めなかったとする", arguments: [
        StubPanelTree.Attribute.children, .role, .title,
    ])
    func vanishedDescendantIsUnavailable(attribute: StubPanelTree.Attribute) throws {
        let tree = StubPanelTree()
        let dialog = tree.add(Fixtures.dialog(id: "open", [
            StubNode(id: "group", role: "AXGroup", children: [Fixtures.fileList(role: "AXBrowser")]),
            StubNode(id: "button", role: "AXButton", title: "開く"),
        ]))
        let vanished: StubElement = switch attribute {
        case .children, .role:
            StubElement("group")
        default:
            StubElement("button")
        }
        tree.failures[vanished] = .elementGone

        #expect(throws: PanelTreeReadError.unavailable) {
            try OpenPanelClassifier.classify(dialog, reader: tree)
        }
    }
}
