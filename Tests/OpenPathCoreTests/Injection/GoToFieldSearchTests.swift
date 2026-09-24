import Testing

import OpenPathCore

@Suite("GoToFieldSearch: 移動先シートの入力欄を探す（DSN-001 §3.2、Issue #74）")
struct GoToFieldSearchTests {
    /// 旧来の移動先シート（「フォルダへ移動:」のコンボボックスと「移動」「キャンセル」ボタン）。
    private static func classicGoToSheet(goTitle: String = "移動") -> FakeAXElement {
        .sheet("go-to", [
            .comboBox("path"),
            .button("cancel", title: "キャンセル"),
            .button("go", title: goTitle),
        ])
    }

    /// ⌘⇧G を送る前の NSOpenPanel の中身（検索フィールド、サイドバー、確定ボタン）。
    private static let panelContents: [FakeAXElement] = [
        .searchField("search"),
        .outline("sidebar", [.textField("row-editor", placeholder: "path")]),
        .button("cancel-panel", title: "キャンセル"),
        .button("open", title: "開く"),
    ]

    @Test("移動先シートの入力欄と、同じシートの「移動」/「Go」ボタンを組にして返す", arguments: ["移動", "Go"])
    func findsFieldAndGoButtonInSheet(goTitle: String) throws {
        let panel = FakeAXElement.dialog(Self.panelContents + [Self.classicGoToSheet(goTitle: goTitle)])

        let match = try #require(try FakeAXSearch.goToField(in: panel))

        #expect(match.field.name == "path")
        #expect(match.goButton?.name == "go")
    }

    @Test("macOS 13 以降の移動先シート（placeholder も「移動」ボタンも無い）の入力欄を AXIdentifier で見つけ、同じシートの候補リストと組にする")
    func findsModernGoToFieldByIdentifier() throws {
        let panel = FakeAXElement.standardWindow([
            .group("toolbar", [.searchField("search")]),
            .modernGoToSheet(rows: [.suggestionHeaderRow, .suggestionRow("/Users/me/Library")]),
        ])

        let match = try #require(try FakeAXSearch.goToField(in: panel))

        #expect(match.field.name == "path")
        #expect(match.goButton == nil)
        #expect(match.suggestionList?.name == "suggestions")
    }

    @Test("AXIdentifier の入力欄を、placeholder だけで判定した入力欄や「移動」ボタンと組になる入力欄より優先する")
    func prefersFieldWithGoToIdentifier() throws {
        let panel = FakeAXElement.dialog([
            .textField("accessory", placeholder: "Path"),
            .sheet("legacy", [.comboBox("legacy-path"), .button("go", title: "移動")]),
            .modernGoToSheet(),
        ])

        #expect(try FakeAXSearch.goToField(in: panel)?.field.name == "path")
    }

    @Test("別のシートにある候補リストは組にしない")
    func doesNotPairSuggestionListInAnotherSheet() throws {
        let panel = FakeAXElement.dialog([
            .sheet("go-to", [.pathTextField("path")]),
            .sheet("other", [.suggestionTable([])]),
        ])

        let match = try #require(try FakeAXSearch.goToField(in: panel))

        #expect(match.suggestionList == nil)
    }

    @Test("通常のウィンドウでは、シートの外にある AXIdentifier の入力欄も使わない")
    func ignoresIdentifiedFieldOutsideSheetsInStandardWindow() throws {
        let hostWindow = FakeAXElement.standardWindow([.pathTextField("path")])

        #expect(try FakeAXSearch.goToField(in: hostWindow) == nil)
    }

    @Test("「移動」ボタンが無くても、placeholder がパスを示す入力欄なら返す（ボタンは無し）")
    func findsFieldByPlaceholderWithoutGoButton() throws {
        let panel = FakeAXElement.dialog(Self.panelContents + [
            .sheet("go-to", [.textField("path", placeholder: "パスを入力")]),
        ])

        let match = try #require(try FakeAXSearch.goToField(in: panel))

        #expect(match.field.name == "path")
        #expect(match.goButton == nil)
    }

    @Test("パネルの検索フィールドは、パスを示す placeholder でも「移動」と同じシートにあっても選ばない")
    func ignoresSearchField() throws {
        let onlySearchField = FakeAXElement.dialog([
            .sheet("go-to", [.searchField("search"), .button("go", title: "Go")]),
        ])
        let withPathField = FakeAXElement.dialog([
            .sheet("go-to", [.searchField("search"), .comboBox("path"), .button("go", title: "Go")]),
        ])

        #expect(try FakeAXSearch.goToField(in: onlySearchField) == nil)
        #expect(try FakeAXSearch.goToField(in: withPathField)?.field.name == "path")
    }

    @Test("移動先シートが無ければ nil（パネル内の他の入力欄を使わない）")
    func returnsNilWithoutGoToSheet() throws {
        let panel = FakeAXElement.dialog(Self.panelContents + [.textField("accessory")])

        #expect(try FakeAXSearch.goToField(in: panel) == nil)
    }

    @Test("「移動」ボタンと別のシートにある入力欄は組にしない")
    func doesNotPairFieldWithGoButtonInAnotherSheet() throws {
        let panel = FakeAXElement.dialog([
            .textField("accessory"),
            .sheet("other", [.button("go", title: "移動")]),
        ])

        #expect(try FakeAXSearch.goToField(in: panel) == nil)
    }

    @Test("通常のウィンドウでは、シートの外の要素を使わない（パネルが閉じた後にホストアプリの画面を操作しないため）")
    func ignoresElementsOutsideSheetsInStandardWindow() throws {
        let hostWindow = FakeAXElement.standardWindow([
            .textField("address", placeholder: "Path"),
            .button("go", title: "Go"),
        ])

        #expect(try FakeAXSearch.goToField(in: hostWindow) == nil)
    }

    @Test("通常のウィンドウでも、シートとして付いたパネルの上の移動先シートは使う（サンドボックスアプリのパネル）")
    func findsGoToSheetOnPanelSheet() throws {
        let hostWindow = FakeAXElement.standardWindow([
            .textField("address", placeholder: "Path"),
            .sheet("open-panel", Self.panelContents + [Self.classicGoToSheet()]),
        ])

        let match = try #require(try FakeAXSearch.goToField(in: hostWindow))

        #expect(match.field.name == "path")
        #expect(match.goButton?.name == "go")
    }

    @Test("「移動」ボタンのあるシートの入力欄を、placeholder だけで判定した入力欄より優先する")
    func prefersFieldPairedWithGoButton() throws {
        let panel = FakeAXElement.dialog([
            .textField("accessory", placeholder: "Path"),
            Self.classicGoToSheet(),
        ])

        #expect(try FakeAXSearch.goToField(in: panel)?.field.name == "path")
    }

    @Test("ファイル一覧の中へは降りない")
    func doesNotDescendIntoFileLists() throws {
        let panel = FakeAXElement.dialog([.outline("files", [Self.classicGoToSheet()])])

        #expect(try FakeAXSearch.goToField(in: panel) == nil)
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let panel = FakeAXElement.dialog([
            .textField("accessory", placeholder: "検索"),
            .sheet("go-to", [.textField("path", placeholder: "パス"), .button("cancel", title: "キャンセル")]),
            .sheet("modern", [.suggestionTable([])]),
        ])
        let fullScan = AXOperationCounter()
        #expect(try FakeAXSearch.goToField(in: panel, counter: fullScan) != nil)

        for limit in 0..<fullScan.value {
            let counter = AXOperationCounter()
            #expect(throws: ScanCutoff.Reached.self) {
                try FakeAXSearch.goToField(in: panel, counter: counter, cutoff: counter.cutoff(afterOperations: limit))
            }
            #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
        }
    }
}
